import Foundation
import Network
import WebKit
import AppKit

// MARK: - HTTP Primitives

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    var taskId: UUID? {
        guard let raw = headers["x-task-id"] else { return nil }
        return UUID(uuidString: raw)
    }

    var bodyJSON: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    func queryParam(_ key: String) -> String? { query[key] }

    static func parse(from data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let fullPath = parts[1]

        // Split path and query string
        var path = fullPath
        var query: [String: String] = [:]
        if let qIdx = fullPath.firstIndex(of: "?") {
            path = String(fullPath[fullPath.startIndex..<qIdx])
            let qs = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    let k = kv[0].removingPercentEncoding ?? kv[0]
                    let v = kv[1].removingPercentEncoding ?? kv[1]
                    query[k] = v
                }
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colonRange = line.range(of: ": ") {
                let key = String(line[line.startIndex..<colonRange.lowerBound]).lowercased()
                let value = String(line[colonRange.upperBound...])
                headers[key] = value
            }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let bodyData = contentLength > 0
            ? Data(data[bodyStart...].prefix(contentLength))
            : Data()

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: bodyData)
    }
}

private struct HTTPResponse {
    let status: Int
    let contentType: String
    let body: Data

    var statusLine: String {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 500: reason = "Internal Server Error"
        default: reason = "Unknown"
        }
        return "HTTP/1.1 \(status) \(reason)"
    }

    var rawData: Data {
        var header = "\(statusLine)\r\n"
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"
        var data = header.data(using: .utf8)!
        data.append(body)
        return data
    }

    static func json(_ dict: [String: Any], status: Int = 200) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
        return HTTPResponse(status: status, contentType: "application/json", body: body)
    }

    static func png(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, contentType: "image/png", body: data)
    }

    static func error(_ message: String, status: Int = 400) -> HTTPResponse {
        json(["ok": false, "error": message], status: status)
    }

    static func notFound() -> HTTPResponse {
        error("Not found", status: 404)
    }
}

// MARK: - Browser HTTP Server

/// NWListener-based HTTP/1.1 server on a single port (default 9222).
/// All tasks share this one server — requests are routed by the X-Task-Id header.
@MainActor
final class BrowserHTTPServer: BrowserAPIServerProtocol {

    static let shared = BrowserHTTPServer()

    private var listener: NWListener?
    private var registry: [UUID: BrowserState] = [:]

    // MARK: - Lifecycle

    func start(port: UInt16 = 9222) throws {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw URLError(.badURL)
        }
        let l = try NWListener(using: params, on: nwPort)
        l.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.accept(conn) }
        }
        l.start(queue: .global(qos: .utility))
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    func registerTask(id: UUID, state: BrowserState) {
        registry[id] = state
        if listener == nil { try? start() }
    }

    func unregisterTask(id: UUID) {
        registry.removeValue(forKey: id)
        if registry.isEmpty { stop() }
    }

    // MARK: - Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let content { accumulated.append(content) }

            // Wait for complete headers
            guard accumulated.range(of: Data("\r\n\r\n".utf8)) != nil else {
                if !isComplete { self.receive(on: connection, buffer: accumulated) }
                return
            }

            guard let req = HTTPRequest.parse(from: accumulated) else {
                Task { @MainActor in self.send(HTTPResponse.error("Bad request"), on: connection) }
                return
            }

            // Check body is fully received
            let contentLength = Int(req.headers["content-length"] ?? "0") ?? 0
            if contentLength > 0 && req.body.count < contentLength {
                self.receive(on: connection, buffer: accumulated)
                return
            }

            Task { @MainActor in
                let resp = await self.dispatch(req)
                self.send(resp, on: connection)
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let data = response.rawData
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Routing

    private func dispatch(_ req: HTTPRequest) async -> HTTPResponse {
        // Resolve task state from X-Task-Id header
        let state: BrowserState?
        if let taskId = req.taskId {
            state = registry[taskId]
        } else {
            // No header — use most recently registered task (single-task convenience)
            state = registry.values.first
        }

        guard let state else {
            return HTTPResponse.error("No task found. Include X-Task-Id header.", status: 404)
        }

        switch (req.method, req.path) {
        case (_, "/capabilities"):  return capabilities(state)
        case ("GET", "/url"):       return await currentURL(state)
        case ("POST", "/navigate"): return await navigate(req, state)
        case ("POST", "/reload"):   return await reload(state)
        case ("GET", "/screenshot"),
             ("POST", "/screenshot"): return await screenshot(req, state)
        case ("POST", "/click"):    return await click(req, state)
        case ("POST", "/type"):     return await type(req, state)
        case ("GET", "/dom"):       return await dom(req, state)
        case ("POST", "/evaluate"): return await evaluate(req, state)
        case ("GET", "/console"):   return console(req, state)
        case ("GET", "/network"):   return network(req, state)
        default:                    return HTTPResponse.notFound()
        }
    }

    // MARK: - Endpoint implementations

    private func capabilities(_ state: BrowserState) -> HTTPResponse {
        HTTPResponse.json([
            "ok": true,
            "url": state.url?.absoluteString as Any,
            "title": state.title as Any,
            "isLoading": state.isLoading,
            "endpoints": ["/capabilities", "/url", "/navigate", "/reload", "/screenshot",
                          "/click", "/type", "/dom", "/evaluate", "/console", "/network"]
        ])
    }

    private func currentURL(_ state: BrowserState) async -> HTTPResponse {
        HTTPResponse.json([
            "ok": true,
            "url": state.url?.absoluteString as Any,
            "title": state.title as Any
        ])
    }

    private func navigate(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let urlStr = req.bodyJSON?["url"] as? String,
              let url = URL(string: urlStr) else {
            return HTTPResponse.error("Missing or invalid 'url' in body")
        }
        state.navigate(to: url)
        // Brief yield so WKWebView starts the load
        try? await Task.sleep(nanoseconds: 100_000_000)
        return HTTPResponse.json(["ok": true, "url": urlStr])
    }

    private func reload(_ state: BrowserState) async -> HTTPResponse {
        state.reload()
        return HTTPResponse.json(["ok": true])
    }

    private func screenshot(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let webView = state.webView else {
            return HTTPResponse.error("No active web view")
        }

        // Optional: crop to element matching CSS selector
        var snapshotRect: CGRect? = nil
        let selector = req.queryParam("selector") ?? (req.bodyJSON?["selector"] as? String)
        if let sel = selector, !sel.isEmpty {
            let escaped = sel.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "'", with: "\\'")
            let js = """
            (function(){
              var el = document.querySelector('\(escaped)');
              if (!el) return null;
              var r = el.getBoundingClientRect();
              return {x:r.left,y:r.top,w:r.width,h:r.height};
            })()
            """
            let rectResult = try? await webView.evaluateJavaScript(js)
            if let dict = rectResult as? [String: Double] {
                let rect = CGRect(x: dict["x"] ?? 0, y: dict["y"] ?? 0,
                                  width: dict["w"] ?? 0, height: dict["h"] ?? 0)
                if !rect.isEmpty { snapshotRect = rect }
            }
        }

        let config = WKSnapshotConfiguration()
        if let rect = snapshotRect { config.rect = rect }

        let image: NSImage? = await withCheckedContinuation { cont in
            webView.takeSnapshot(with: config) { img, _ in cont.resume(returning: img) }
        }

        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return HTTPResponse.error("Screenshot failed")
        }

        return HTTPResponse.png(pngData)
    }

    private func click(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let selector = req.bodyJSON?["selector"] as? String else {
            return HTTPResponse.error("Missing 'selector' in body")
        }
        guard let webView = state.webView else { return HTTPResponse.error("No active web view") }

        let escaped = jsEscape(selector)
        let js = "var el=document.querySelector('\(escaped)');if(!el)throw new Error('Element not found');el.click();el.tagName+'.'+el.className"
        do {
            let result = try await webView.evaluateJavaScript(js)
            return HTTPResponse.json(["ok": true, "element": result as? String ?? selector])
        } catch {
            return HTTPResponse.error(error.localizedDescription)
        }
    }

    private func type(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let selector = req.bodyJSON?["selector"] as? String,
              let text = req.bodyJSON?["text"] as? String else {
            return HTTPResponse.error("Missing 'selector' or 'text' in body")
        }
        guard let webView = state.webView else { return HTTPResponse.error("No active web view") }

        let escSel = jsEscape(selector)
        let escText = jsEscape(text)
        let js = """
        var el=document.querySelector('\(escSel)');
        if(!el)throw new Error('Element not found');
        el.focus();el.value='\(escText)';
        el.dispatchEvent(new Event('input',{bubbles:true}));
        el.dispatchEvent(new Event('change',{bubbles:true}));
        true
        """
        do {
            try await webView.evaluateJavaScript(js)
            return HTTPResponse.json(["ok": true])
        } catch {
            return HTTPResponse.error(error.localizedDescription)
        }
    }

    private func dom(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let webView = state.webView else { return HTTPResponse.error("No active web view") }

        let selector = req.queryParam("selector")
        let js: String
        if let sel = selector, !sel.isEmpty {
            let escaped = jsEscape(sel)
            js = "var el=document.querySelector('\(escaped)');el?el.outerHTML:null"
        } else {
            js = "document.documentElement.outerHTML"
        }

        do {
            let result = try await webView.evaluateJavaScript(js)
            guard let html = result as? String else {
                return HTTPResponse.error("Element not found", status: 404)
            }
            return HTTPResponse.json(["ok": true, "html": html])
        } catch {
            return HTTPResponse.error(error.localizedDescription)
        }
    }

    private func evaluate(_ req: HTTPRequest, _ state: BrowserState) async -> HTTPResponse {
        guard let script = req.bodyJSON?["script"] as? String else {
            return HTTPResponse.error("Missing 'script' in body")
        }
        guard let webView = state.webView else { return HTTPResponse.error("No active web view") }

        do {
            let result = try await webView.evaluateJavaScript(script)
            let serialized: Any
            if let r = result {
                serialized = (JSONSerialization.isValidJSONObject(r)) ? r : String(describing: r)
            } else {
                serialized = NSNull()
            }
            return HTTPResponse.json(["ok": true, "result": serialized])
        } catch {
            return HTTPResponse.error(error.localizedDescription)
        }
    }

    private func console(_ req: HTTPRequest, _ state: BrowserState) -> HTTPResponse {
        let since = Double(req.queryParam("since") ?? "0") ?? 0
        let entries = state.consoleLogs
            .filter { $0.timestamp >= since }
            .map { ["level": $0.level, "text": $0.text, "timestamp": $0.timestamp] as [String: Any] }
        return HTTPResponse.json(["ok": true, "entries": entries])
    }

    private func network(_ req: HTTPRequest, _ state: BrowserState) -> HTTPResponse {
        let since = Double(req.queryParam("since") ?? "0") ?? 0
        let entries = state.networkLogs
            .filter { $0.timestamp >= since }
            .map { e -> [String: Any] in
                var d: [String: Any] = ["url": e.url, "method": e.method,
                                        "status": e.status, "duration": e.duration,
                                        "timestamp": e.timestamp]
                if let err = e.error { d["error"] = err }
                return d
            }
        return HTTPResponse.json(["ok": true, "entries": entries])
    }

    // MARK: - Helpers

    private func jsEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "'", with: "\\'")
         .replacingOccurrences(of: "\n", with: "\\n")
    }
}
