import Foundation

struct LangflowClient {
    let baseURL: URL
    let flowID: String
    let apiKey: String

    private var runURL: URL { baseURL.appendingPathComponent("/api/v1/run/\(flowID)") }

    func ask(question: String, sessionID: String) async throws -> String {
        var req = URLRequest(url: runURL)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = [
            "input_value": question,
            "input_type": "chat",
            "output_type": "chat",
            "session_id": sessionID
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "Langflow", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad status"])
        }

        return try LangflowDecoder.extractText(from: data)
    }

    func stream(question: String, sessionID: String) -> AsyncThrowingStream<String, Error> {
        var comps = URLComponents(url: runURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "stream", value: "true")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue(apiKey, forHTTPHeaderField: "x-api-key")

        let body: [String: Any] = [
            "input_value": question,
            "input_type": "chat",
            "output_type": "chat",
            "session_id": sessionID
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        throw NSError(domain: "Langflow", code: 2, userInfo: [NSLocalizedDescriptionKey: "Bad status"])
                    }
                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        if let chunk = LangflowStreamParser.tokenChunk(fromLine: line) {
                            continuation.yield(chunk)
                        }
                        if LangflowStreamParser.isEndEvent(line: line) {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum LangflowDecoder {
    struct Response: Decodable {
        struct OutWrap: Decodable {
            struct InnerOut: Decodable {
                struct Results: Decodable {
                    struct Message: Decodable { let text: String }
                    let message: Message
                }
                let results: Results
            }
            let outputs: [InnerOut]
        }
        let outputs: [OutWrap]
    }

    static func extractText(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.outputs.first?.outputs.first?.results.message.text ?? ""
    }
}

enum LangflowStreamParser {
    static func tokenChunk(fromLine line: String) -> String? {
        guard line.contains("\"event\"") else { return nil }
        if line.contains("\"event\":\"token\""),
           let range = line.range(of: "\"chunk\":\"") {
            let after = line[range.upperBound...]
            if let end = after.firstIndex(of: "\"") {
                return String(after[..<end])
            }
        }
        return nil
    }

    static func isEndEvent(line: String) -> Bool {
        line.contains("\"event\":\"end\"")
    }
}
