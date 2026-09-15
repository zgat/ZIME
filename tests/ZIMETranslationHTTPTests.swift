import Foundation

// Every URL is intercepted, including unexpected redirect targets. No sockets,
// real credentials, Keychain access or user URLSession state are used.
private final class HTTPFixtureState: @unchecked Sendable {
  struct Plan {
    var status = 200
    var data = Data()
    var error: URLError.Code?
    var redirect = false
    var nonHTTP = false
    var stall = false
    var omitHeaders = false
  }
  let lock = NSLock()
  private var plan = Plan()
  private var requests: [URLRequest] = []
  private var stops = 0
  func reset(_ value: Plan) { lock.withLock { plan = value; requests = []; stops = 0 } }
  func start(_ request: URLRequest) -> Plan { lock.withLock { requests.append(request); return plan } }
  func stop() { lock.withLock { stops += 1 } }
  var started: Bool { lock.withLock { !requests.isEmpty } }
  var count: Int { lock.withLock { requests.count } }
  var stopCount: Int { lock.withLock { stops } }
}

private final class HTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
  static let state = HTTPFixtureState()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let plan = Self.state.start(request)
    precondition(request.httpMethod == "POST", "transport changed request method")
    precondition(request.cachePolicy == .reloadIgnoringLocalCacheData && request.timeoutInterval == 10)
    if let error = plan.error {
      client!.urlProtocol(self, didFailWithError: URLError(error)); return
    }
    if plan.omitHeaders { return }
    let response = HTTPURLResponse(url: request.url!, statusCode: plan.redirect ? 302 : plan.status,
      httpVersion: "HTTP/1.1", headerFields: plan.redirect ? ["Location": "https://redirect.invalid/secret"] : nil)!
    if plan.redirect {
      client!.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://redirect.invalid/secret")!),
        redirectResponse: response)
      // If the delegate declines, the original 302 response still needs to
      // finish; merely announcing a redirect leaves URLProtocol loading open.
    }
    let delivered: URLResponse = plan.nonHTTP
      ? URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil) : response
    client!.urlProtocol(self, didReceive: delivered, cacheStoragePolicy: .notAllowed)
    // Deliver in separate chunks, including splits inside UTF-8/JSON tokens.
    for start in stride(from: 0, to: plan.data.count, by: 17) {
      client!.urlProtocol(self, didLoad: plan.data.subdata(in: start..<min(start + 17, plan.data.count)))
    }
    if !plan.stall { client!.urlProtocolDidFinishLoading(self) }
  }
  override func stopLoading() { Self.state.stop() }
}

@main struct ZIMETranslationHTTPTests {
  static func configuration(_ provider: ZIMETranslationConfiguration.Provider = .compatible) -> ZIMETranslationConfiguration {
    var value = ZIMETranslationConfiguration()
    value.enabled = true; value.provider = provider
    value.baseURL = "https://translation.invalid/v1"; value.model = "offline-fixture"
    return value
  }

  static func translate(_ provider: ZIMETranslationConfiguration.Provider = .compatible) async throws -> String {
    try await ZIMETranslationHTTP.translate(configuration: configuration(provider),
      credentials: .init(identifier: "synthetic-id", secret: "synthetic-secret"), text: "你", chinese: true,
      makeSession: { config, delegate in
        precondition(config.urlCache == nil && config.httpCookieStorage == nil && config.urlCredentialStorage == nil)
        precondition(config.timeoutIntervalForResource == 12, "resource timeout removed")
        config.protocolClasses = [HTTPFixtureProtocol.self]
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
      })
  }

  private static func expectFailure(_ plan: HTTPFixtureState.Plan, matches: (Error) -> Bool) async {
    HTTPFixtureProtocol.state.reset(plan)
    do {
      _ = try await translate()
      fatalError("invalid transport response was accepted")
    } catch { precondition(matches(error), "unexpected transport error (status=\(plan.status), redirect=\(plan.redirect)): \(error)") }
    precondition(HTTPFixtureProtocol.state.count == 1, "transport retried or followed a redirect")
  }

  static func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    fatalError("URLProtocol event deadline exceeded")
  }

  static func main() async throws {
    // An unbounded stream or broken cancellation must fail, never hang CI.
    let watchdog = DispatchWorkItem { fatalError("HTTP fixture exceeded 25 seconds") }
    DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: watchdog)
    defer { watchdog.cancel() }
    let raw = "  you (informal) / yourself\n第二行  "
    let bodies: [(ZIMETranslationConfiguration.Provider, [String: Any])] = [
      (.compatible, ["choices": [["message": ["content": raw]]]]),
      (.deepl, ["translations": [["text": raw]]]),
      (.baidu, ["trans_result": [["dst": raw]]]),
      (.tencent, ["Response": ["TargetText": raw]])
    ]
    for (provider, body) in bodies {
      HTTPFixtureProtocol.state.reset(.init(data: try JSONSerialization.data(withJSONObject: body)))
      let result = try await translate(provider)
      precondition(result == raw && HTTPFixtureProtocol.state.count == 1, "transport altered API commit text")
    }
    for status in [300, 401, 403, 429, 500, 503] {
      await expectFailure(.init(status: status)) {
        if case ZIMETranslationError.http(let actual) = $0 { return actual == status }; return false
      }
    }
    await expectFailure(.init(nonHTTP: true)) {
      if case ZIMETranslationError.http(0) = $0 { return true }; return false
    }
    await expectFailure(.init(redirect: true)) {
      if case ZIMETranslationError.http(302) = $0 { return true }; return false
    }
    for code: URLError.Code in [.timedOut, .networkConnectionLost, .notConnectedToInternet] {
      await expectFailure(.init(error: code)) { ($0 as? URLError)?.code == code }
    }
    for malformed in ["", "{", "{\"choices\":[]}", "{\"choices\":[{\"message\":{\"content\":\"\"}}]}"] {
      await expectFailure(.init(data: Data(malformed.utf8))) { _ in true }
    }
    let valid = try JSONSerialization.data(withJSONObject: bodies[0].1)
    var boundary = valid + Data(repeating: 32, count: 65_536 - valid.count)
    HTTPFixtureProtocol.state.reset(.init(data: boundary))
    let result = try await translate()
    precondition(result == raw, "exact 64 KiB response was rejected")
    boundary.append(32)
    // Never finish this stream: rejection must happen while reading, not only
    // in parse() after buffering an arbitrary response to completion.
    await expectFailure(.init(data: boundary, stall: true)) {
      if case ZIMETranslationError.response = $0 { return true }; return false
    }
    for omitHeaders in [false, true] {
      HTTPFixtureProtocol.state.reset(.init(stall: true, omitHeaders: omitHeaders))
      let task = Task { try await translate() }
      try await waitUntil { HTTPFixtureProtocol.state.started }
      task.cancel()
      do { _ = try await task.value; fatalError("cancelled request returned a translation") }
      catch { precondition(error is CancellationError || (error as? URLError)?.code == .cancelled) }
      try await waitUntil { HTTPFixtureProtocol.state.stopCount > 0 }
      precondition(HTTPFixtureProtocol.state.count == 1)
    }
    print("ZIME HTTP transport: PASS (4 providers; status/redirect/errors/JSON; 64 KiB streaming boundary; cancellation before/after headers; private session; zero network)")
  }
}
