#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
# Exercise the production release client with an in-process HTTP transport;
# neither credentials nor network access are required.
require "stringio"
load File.expand_path("../scripts/upstream-sync", __dir__)

module GitHubReleaseRedirectTest
  OLD = "amzxyz/RIME-LMDG".freeze
  CANONICAL = "amzxyz/rime-wanxiang-data".freeze
  ASSET = "wanxiang-lts-zh-hans.gram".freeze
  OLD_API = "https://api.github.com/repos/#{OLD}/releases/tags/LTS".freeze
  CANONICAL_API = "https://api.github.com/repos/#{CANONICAL}/releases/tags/LTS".freeze
  NUMERIC_API = "https://api.github.com/repositories/880034560/releases/tags/LTS".freeze
  TOKEN = "offline-test-token-not-a-real-credential".freeze
  class << self
    attr_accessor :queue, :requests, :checks, :timeout_calls, :timeout_depth
  end
  self.checks = 0

  def self.assert(value, message)
    raise message unless value
  end

  def self.source(slug = OLD)
    {"repository" => "https://github.com/#{slug}.git", "release" => "LTS",
      "asset" => ASSET, "asset_id" => 123, "bytes" => 456, "sha256" => "a" * 64,
      "asset_api_url" => "https://api.github.com/repos/#{slug}/releases/assets/123",
      "asset_download_url" => "https://github.com/#{slug}/releases/download/LTS/#{ASSET}"}
  end

  def self.metadata(slug = CANONICAL)
    api = "https://api.github.com/repos/#{slug}/releases/789"
    {"id" => 789, "url" => api, "assets_url" => "#{api}/assets", "tag_name" => "LTS",
      "html_url" => "https://github.com/#{slug}/releases/tag/LTS",
      "assets" => [{"name" => ASSET, "id" => 123, "size" => 456,
        "state" => "uploaded", "digest" => "sha256:#{'a' * 64}",
        "url" => "https://api.github.com/repos/#{slug}/releases/assets/123",
        "browser_download_url" => "https://github.com/#{slug}/releases/download/LTS/#{ASSET}"}]}
  end

  def self.response(code, body = nil, location = nil)
    klass = Net::HTTPResponse::CODE_TO_OBJ.fetch(code.to_s)
    result = klass.new("1.1", code.to_s, "fixture")
    result["Location"] = location if location
    bytes = body.is_a?(Hash) || body.is_a?(Array) ? JSON.generate(body) : body
    result.define_singleton_method(:body) { bytes }
    result
  end

  def self.with_http(plan, token: TOKEN)
    self.queue = plan.dup
    self.requests = []
    self.timeout_calls = []
    self.timeout_depth = 0
    previous = ENV["GH_TOKEN"]
    ENV["GH_TOKEN"] = token
    yield
    assert(queue.empty?, "unused HTTP fixtures: #{queue.length}")
    assert(timeout_calls == [60] && timeout_depth.zero?,
      "one 60-second timeout must surround the entire redirect chain")
  ensure
    ENV["GH_TOKEN"] = previous
  end

  def self.request(request, host, port, options)
    assert(timeout_depth == 1, "HTTP hop escaped the single total-chain timeout")
    assert(host == "api.github.com" && port == 443 && options[:use_ssl], "unsafe transport origin")
    assert(options.values_at(:open_timeout, :read_timeout, :write_timeout) == [10, 20, 20],
      "connection, read and write timeouts must be bounded")
    expected_auth = ENV["GH_TOKEN"].to_s.empty? ? nil : "Bearer #{TOKEN}"
    assert(request["Authorization"] == expected_auth, "incorrect request credential policy")
    assert(request["Accept"] == "application/vnd.github+json" &&
      request["X-GitHub-Api-Version"] == "2022-11-28", "missing GitHub API headers")
    self.requests << request.uri.to_s
    expected_uri, result = queue.shift
    assert(expected_uri == request.uri.to_s, "unexpected HTTP request: #{request.uri}")
    raise result if result.is_a?(Exception)
    result
  end

  def self.fails(message)
    previous = $stderr
    capture = StringIO.new
    $stderr = capture
    begin
      yield
    rescue SystemExit => error
      assert(error.status == 1, "unexpected failure exit status")
      assert(capture.string.include?(message), "wrong failure: #{capture.string}")
      return
    end
    raise "expected failure: #{message}"
  ensure
    $stderr = previous
  end

  def self.check(name)
    yield
    self.checks += 1
  rescue StandardError => error
    raise "#{name}: #{error.message}"
  end

  def self.renamed_plan(payload = metadata)
    [[OLD_API, response(301, nil, NUMERIC_API)], [NUMERIC_API, response(200, payload)]]
  end

  def self.run
    check("canonical direct metadata") do
      with_http([[CANONICAL_API, response(200, metadata)]]) do
        assert(release_asset_status(source(CANONICAL)).last == "current", "canonical asset not current")
      end
    end
    check("old direct metadata without migration") do
      with_http([[OLD_API, response(200, metadata(OLD))]], token: nil) do
        assert(release_asset_status(source).last == "current", "original asset not current")
      end
    end
    check("301 numeric repository preserves immutable current identity") do
      with_http(renamed_plan) do
        assert(release_asset_status(source).last == "current", "rename alone must not mark content drift")
      end
    end
    check("all supported redirect statuses and relative destinations") do
      [301, 302, 303, 307, 308].each do |code|
        with_http([[OLD_API, response(code, nil, "/repos/#{CANONICAL}/releases/tags/LTS")],
          [CANONICAL_API, response(200, metadata)]]) do
          assert(release_asset_status(source).last == "current", "redirect #{code} failed")
        end
      end
    end
    check("one total-chain timeout surrounds every authenticated redirect hop") do
      with_http([[OLD_API, response(301, nil, NUMERIC_API)],
        [NUMERIC_API, response(308, nil, CANONICAL_API)],
        [CANONICAL_API, response(200, metadata)]]) do
        assert(release_asset_status(source).last == "current", "multi-hop failed")
      end
    end
    check("maximum three redirects succeed") do
      alias_uri = "https://api.github.com/repos/alias/repo/releases/tags/LTS"
      with_http([[OLD_API, response(301, nil, alias_uri)],
        [alias_uri, response(302, nil, NUMERIC_API)], [NUMERIC_API, response(307, nil, CANONICAL_API)],
        [CANONICAL_API, response(200, metadata)]]) do
        assert(release_asset_status(source).last == "current", "bounded chain failed")
      end
    end
    check("HTTP errors fail closed") do
      [304, 400, 401, 403, 404, 429, 500].each do |code|
        with_http([[OLD_API, response(code)]]) do
          fails("HTTP #{code}") { release_asset_status(source) }
        end
      end
    end
    check("unsafe redirect destinations never receive a request or credentials") do
      ["http://api.github.com/repos/a/b/releases/tags/LTS",
        "https://evil.example/repos/a/b/releases/tags/LTS",
        "https://api.github.com.evil.example/repos/a/b/releases/tags/LTS",
        "//evil.example/repos/a/b/releases/tags/LTS",
        "https://user:password@api.github.com/repos/a/b/releases/tags/LTS",
        "https://api.github.com:444/repos/a/b/releases/tags/LTS",
        "https://api.github.com/repos/a/b/releases/tags/other",
        "https://api.github.com/repos/a/b/releases/assets/123",
        "https://api.github.com/repos/a/b/releases/tags/LTS?token=bad",
        "https://api.github.com/repos/a/b/releases/tags/LTS#fragment",
        "file:///repos/a/b/releases/tags/LTS"].each do |location|
        with_http([[OLD_API, response(301, nil, location)]]) do
          fails("unsafe GitHub release API URL") { release_asset_status(source) }
          assert(requests.length == 1, "unsafe origin received a follow-up request")
        end
      end
    end
    check("missing and malformed redirect locations") do
      [nil, "", "https://api.github.com/[invalid"].each do |location|
        with_http([[OLD_API, response(301, nil, location)]]) do
          fails(location.to_s.empty? ? "has no Location" : "invalid GitHub release API redirect URL") do
            release_asset_status(source)
          end
        end
      end
    end
    check("redirect loops terminate before replay") do
      with_http([[OLD_API, response(301, nil, NUMERIC_API)],
        [NUMERIC_API, response(301, nil, OLD_API)]]) do
        fails("redirect loop") { release_asset_status(source) }
        assert(requests.length == 2, "loop request replayed")
      end
    end
    check("redirect cap terminates non-loop chains") do
      uris = (1..5).map { |id| "https://api.github.com/repositories/#{id}/releases/tags/LTS" }
      plan = [[OLD_API, response(301, nil, uris[0])]] +
        uris.first(3).each_with_index.map { |uri, index| [uri, response(301, nil, uris[index + 1])] }
      with_http(plan) { fails("redirect limit exceeded") { release_asset_status(source) } }
    end
    check("network and total-chain timeout errors are controlled") do
      [Net::OpenTimeout.new, Net::ReadTimeout.new, Timeout::Error.new,
        SocketError.new("offline"), OpenSSL::SSL::SSLError.new("invalid certificate")].each do |error|
        with_http([[OLD_API, error]]) { fails("GitHub release lookup failed") { release_asset_status(source) } }
      end
    end
    check("unredirected or mismatched canonical repository cannot migrate identity") do
      with_http([[OLD_API, response(200, metadata)]]) do
        fails("repository changed without a matching API redirect") { release_asset_status(source) }
      end
      with_http([[OLD_API, response(301, nil, "/repos/unrelated/repo/releases/tags/LTS")],
        ["https://api.github.com/repos/unrelated/repo/releases/tags/LTS", response(200, metadata)]]) do
        fails("repository changed without a matching API redirect") { release_asset_status(source) }
      end
    end
    check("immutable id, size and digest changes surface review") do
      [{"id" => 124, "url" => "https://api.github.com/repos/#{CANONICAL}/releases/assets/124"},
        {"size" => 457}, {"digest" => "sha256:#{'b' * 64}"}].each do |change|
        payload = metadata
        payload.fetch("assets").first.merge!(change)
        with_http(renamed_plan(payload)) do
          assert(release_asset_status(source).last.start_with?("review "), "immutable identity drift ignored")
        end
      end
    end
    check("malformed release and asset metadata fail closed") do
      changes = [
        ->(j) { j["id"] = "789" }, ->(j) { j["id"] = 0 }, ->(j) { j["tag_name"] = "other" },
        ->(j) { j["url"] = "https://api.github.com/repos/#{CANONICAL}/releases/790" },
        ->(j) { j["html_url"] = "https://github.com/attacker/repo/releases/tag/LTS" },
        ->(j) { j["assets_url"] = "https://api.github.com/repos/attacker/repo/releases/789/assets" },
        ->(j) { j["assets"] = {} }, ->(j) { j["assets"] = [nil] },
        ->(j) { j["assets"] = [] }, ->(j) { j["assets"] << j["assets"].first.dup },
        ->(j) { j["assets"].first["id"] = "123" }, ->(j) { j["assets"].first["id"] = 0 },
        ->(j) { j["assets"].first["size"] = 0 }, ->(j) { j["assets"].first["state"] = "new" },
        ->(j) { j["assets"].first["digest"] = nil },
        ->(j) { j["assets"].first["url"] = "https://api.github.com/repos/#{OLD}/releases/assets/123" },
        ->(j) { j["assets"].first["url"] = "https://api.github.com/repos/#{CANONICAL}/releases/assets/124" },
        ->(j) { j["assets"].first["browser_download_url"] = source.fetch("asset_download_url") },
        ->(j) { j["assets"].first["browser_download_url"] = "https://github.com/#{CANONICAL}/releases/download/other/#{ASSET}" },
        ->(j) { j.delete("tag_name") }
      ]
      changes.each do |change|
        payload = metadata
        change.call(payload)
        with_http(renamed_plan(payload)) { fails("upstream-sync:") { release_asset_status(source) } }
      end
      ["{invalid", "[]", "null"].each do |body|
        with_http([[OLD_API, response(200, body)]]) { fails("metadata") { release_asset_status(source) } }
      end
    end
    puts "GitHub release redirects: PASS (#{checks} groups; no network or real credentials)"
  end
end

original_timeout = Timeout.method(:timeout)
Timeout.singleton_class.send(:define_method, :timeout) do |duration, *arguments, &block|
  GitHubReleaseRedirectTest.timeout_calls << duration
  GitHubReleaseRedirectTest.timeout_depth += 1
  begin
    original_timeout.call(duration, *arguments, &block)
  ensure
    GitHubReleaseRedirectTest.timeout_depth -= 1
  end
end

Net::HTTP.singleton_class.send(:define_method, :start) do |host, port, **options, &block|
  transport = Object.new
  transport.define_singleton_method(:request) do |request|
    GitHubReleaseRedirectTest.request(request, host, port, options)
  end
  block.call(transport)
end

GitHubReleaseRedirectTest.run
