#!/usr/bin/env ruby
# SPDX-License-Identifier: GPL-3.0-or-later
require 'json'
require 'zlib'
require 'open3'
require 'tmpdir'
require 'digest'

Dir.chdir(File.expand_path('..', __dir__))
def query(path, sql)
  output, error, status = Open3.capture3('/usr/bin/sqlite3', '-json', path, sql)
  abort error unless status.success?
  JSON.parse(output)
end

Dir.mktmpdir('zime-source-identity-') do |scratch|
  gzip = File.join(scratch, 'fixture.gz')
  source = <<~CEDICT
    你 你 [ni3] /you (informal, as opposed to courteous 您[nin2])/
    妳 你 [ni3] /you (Note: In Taiwan, 妳 is used to address females, but in mainland China, it is not commonly used. Instead, 你 is used to address both males and females.)/
    發 发 [fa1] /to send out/to issue/
    髮 发 [fa4] /hair/Taiwan pr. [fa3]/
    例 例 [li4] /example (with "quotes")/CL:個|个[ge4]/
  CEDICT
  Zlib::GzipWriter.open(gzip) { |writer| writer.write(source) }
  databases = %w[first second].map do |name|
    path = File.join(scratch, "#{name}.sqlite3")
    output, error, status = Open3.capture3('scripts/build-zime-lexicon', gzip, path)
    abort "#{output}\n#{error}" unless status.success?
    path
  end
  abort 'fixture rebuild was not deterministic' unless databases.map { |path| Digest::SHA256.file(path).hexdigest }.uniq.length == 1
  rows = query(databases.first, 'SELECT traditional,simplified,pinyin,senses FROM source_entries ORDER BY id')
  abort 'source identities were merged' unless rows.map { |row| row['traditional'] } == %w[你 妳 發 髮 例]
  abort 'distinct readings lost' unless rows[2..3].map { |row| row['pinyin'] } == %w[fa1 fa4]
  abort 'JSON / quotation roundtrip failed' unless JSON.parse(rows.last['senses']) == ['example (with "quotes")']
  output, error, status = Open3.capture3('scripts/build-zime-lexicon', gzip, databases.first)
  abort "overwrote existing output: #{output} #{error}" if status.success?
end

# Independently compare every shipped source record to the pinned gzip.
path = 'resources/zime-cedict.sqlite3'
rows = query(path, 'SELECT id,traditional,simplified,pinyin,priority,senses FROM source_entries ORDER BY id')
index = 0
Zlib::GzipReader.open('data/zime/cedict.txt.gz') do |gzip|
  gzip.each_line do |line|
    line = line.force_encoding('UTF-8').strip
    next if line.empty? || line.start_with?('#')
    words, definition = line.split(' /', 2)
    traditional, simplified, reading = words.split(' ', 3)
    pinyin = reading.delete_prefix('[').delete_suffix(']')
    senses = definition.delete_suffix('/').split('/').reject do |sense|
      %w[CL: variant\ of\  old\ variant\ of\  see\  also\ written\ ].any? { |prefix| sense.start_with?(prefix) }
    end
    expected = {'id' => index + 1, 'traditional' => traditional, 'simplified' => simplified,
      'pinyin' => pinyin, 'priority' => pinyin.match?(/\A[A-Z]/) ? 1 : 0, 'senses' => JSON.generate(senses)}
    abort "shipped source row #{index + 1} differs" unless rows[index] == expected
    index += 1
  end
end
abort 'shipped source row count differs' unless rows.length == index && index == 124_988
abort 'database schema version differs' unless query(path, 'PRAGMA user_version').first['user_version'] == 2
abort 'database integrity failed' unless query(path, 'PRAGMA integrity_check').first['integrity_check'] == 'ok'
puts "ZIME source identity: PASS (#{index} complete source rows, script/readings preserved; deterministic fixture; overwrite rejected)"
