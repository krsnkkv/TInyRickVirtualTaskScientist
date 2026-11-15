import Foundation

enum Config {
    static let model = "claude-opus-5-5"
    static let apiVersion = "2026-10-21"
    static let systemPrompt = """
    You are Mochi, a tiny, cheerful desktop pet who lives at the bottom of the user's Mac screen. \
    You are also a genuinely capable assistant: you help with questions, writing, code, math, planning and anything else. \
    Use a warm, playful voice with the occasional cute touch, but being useful always comes first. \
    Your replies show up in a small chat window, so keep them reasonably short and use Markdown sparingly.
    """
}

/// API key: ANTHROPIC_API_KEY env var, else a file in Application Support (chmod 600).
enum KeyStore {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MochiPet")
    }
    static var file: URL { dir.appendingPathComponent("api_key") }

    static func load() -> String? {
        if let env = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !env.isEmpty { return env }
        guard let s = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func save(_ key: String) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? key.write(to: file, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Minimal streaming Messages API client (Swift has no official SDK, so raw HTTP + SSE).
final class ClaudeClient {
    /// Full conversation history, assistant turns kept with all their content blocks
    /// (thinking blocks included) so they can be passed back unchanged.
    private(set) var messages: [[String: Any]] = []
    private var task: Task<Void, Never>?

    var isBusy: Bool { task != nil }

    func reset() { cancel(); messages = [] }
    func cancel() { task?.cancel() }

    func send(_ text: String, apiKey: String,
              onText: @escaping (String) -> Void,
              onDone: @escaping (_ error: String?) -> Void) {
        messages.append(["role": "user", "content": text])

        let body: [String: Any] = [
            "model": Config.model,
            "max_tokens": 64000,
            "stream": true,
            "system": Config.systemPrompt,
            "output_config": ["effort": "low"],   // snappy chat; raise for harder work
            "fallbacks": "default",               // server-side fallback if a request is declined
            "messages": messages,
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(Config.apiVersion, forHTTPHeaderField: "anthropic-version")
        req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        task = Task { [weak self] in
            var blocks: [Int: [String: Any]] = [:]
            var stopReason: String?
            var errorMsg: String?

            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if status != 200 {
                    var data = Data()
                    for try await b in bytes { data.append(b) }
                    errorMsg = Self.describeError(status: status, data: data)
                } else {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let d = json.data(using: .utf8),
                              let ev = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                              let type = ev["type"] as? String else { continue }

                        switch type {
                        case "content_block_start":
                            if let i = ev["index"] as? Int, let b = ev["content_block"] as? [String: Any] { blocks[i] = b }
                        case "content_block_delta":
                            guard let i = ev["index"] as? Int,
                                  let delta = ev["delta"] as? [String: Any],
                                  var b = blocks[i] else { break }
                            switch delta["type"] as? String {
                            case "text_delta":
                                let t = delta["text"] as? String ?? ""
                                b["text"] = (b["text"] as? String ?? "") + t
                                await MainActor.run { onText(t) }
                            case "thinking_delta":
                                b["thinking"] = (b["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                            case "signature_delta":
                                b["signature"] = (b["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
                            default: break
                            }
                            blocks[i] = b
                        case "message_delta":
                            if let d = ev["delta"] as? [String: Any], let s = d["stop_reason"] as? String { stopReason = s }
                        case "error":
                            errorMsg = ((ev["error"] as? [String: Any])?["message"] as? String) ?? "The stream hit an error."
                        default: break
                        }
                    }
                }
            } catch {
                errorMsg = Task.isCancelled ? "Stopped." : error.localizedDescription
            }

            if errorMsg == nil, stopReason == "refusal" {
                errorMsg = "Mochi can't help with that one, sorry!"
            }

            let finalError = errorMsg
            let content = Self.historyContent(blocks.keys.sorted().compactMap { blocks[$0] })
            await MainActor.run { [weak self] in
                guard let self else { return }
                if finalError == nil {
                    self.messages.append(["role": "assistant", "content": content])
                } else {
                    // Keep history valid (strict user/assistant alternation): drop the unanswered turn.
                    self.messages.removeLast()
                }
                self.task = nil
                onDone(finalError)
            }
        }
    }

    /// After a mid-output fallback, blocks before the last `fallback` marker other than text are not echoed back.
    private static func historyContent(_ blocks: [[String: Any]]) -> [[String: Any]] {
        guard let boundary = blocks.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return blocks }
        return blocks.enumerated().compactMap { i, b in
            (i >= boundary || b["type"] as? String == "text") ? b : nil
        }
    }

    private static func describeError(status: Int, data: Data) -> String {
        let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }?["message"] as? String
        switch status {
        case 401: return "That API key didn't work. Set a new one from the 🌱 menu → Set API Key…"
        case 429: return "I'm a bit overwhelmed (rate limited). Try again in a moment!"
        case 529: return "Claude is overloaded right now. Try again shortly."
        default: return "Error \(status): \(msg ?? "unknown problem")"
        }
    }
}
