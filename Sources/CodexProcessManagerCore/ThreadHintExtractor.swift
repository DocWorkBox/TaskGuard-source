import Foundation

public enum ThreadHintExtractor {
    public static func extract(from process: ManagedProcess) -> ThreadHint? {
        let command = process.commandLine
        let threadId = quotedValue(for: "thread-id", in: command)
        let turnId = quotedValue(for: "turn-id", in: command)
        let payloadCwd = quotedValue(for: "cwd", in: command)
        let displayTitle = extractedTitle(from: command)
        let indexedTitle = threadId.flatMap(CodexSessionIndex.title(for:))

        if threadId != nil || turnId != nil || payloadCwd != nil {
            return ThreadHint(
                threadId: threadId,
                turnId: turnId,
                displayTitle: displayTitle ?? indexedTitle,
                cwd: payloadCwd ?? process.cwd,
                source: .codexTurnPayload,
                confidence: threadId == nil ? 0.75 : 0.95
            )
        }

        if let sessionId = value(after: "--session-id", in: command) {
            let workingDirectory = value(after: "--working-dir", in: command, allowsSpaces: true) ?? process.cwd
            return ThreadHint(
                threadId: sessionId,
                turnId: nil,
                displayTitle: displayTitle
                    ?? CodexSessionIndex.title(for: sessionId)
                    ?? DisplayNameResolver.sessionTitle(cwd: workingDirectory, id: sessionId),
                cwd: workingDirectory,
                source: .commandLine,
                confidence: 0.7
            )
        }

        let cwd = process.cwd ?? value(after: "--working-dir", in: command, allowsSpaces: true)
        if let cwd, cwd.contains("/Documents/Codex/") {
            return ThreadHint(
                threadId: nil,
                turnId: nil,
                displayTitle: displayTitle,
                cwd: cwd,
                source: .workingDirectory,
                confidence: 0.55
            )
        }

        return nil
    }

    private static func quotedValue(for key: String, in text: String) -> String? {
        let marker = "\"\(key)\":\""
        guard let start = text.range(of: marker) else { return nil }
        let valueStart = start.upperBound
        guard let end = text[valueStart...].firstIndex(of: "\"") else { return nil }
        return String(text[valueStart..<end])
    }

    private static func extractedTitle(from text: String) -> String? {
        let candidates = [
            text,
            unescaped(text)
        ]

        for candidate in candidates {
            if let title = quotedValue(for: "title", in: candidate), isUsefulTitle(title) {
                return title
            }

            if let prompt = valueAfterMarker("User prompt:\n", in: candidate), isUsefulTitle(prompt) {
                return prompt
            }

            if let prompt = valueAfterMarker("User prompt:\\n", in: candidate), isUsefulTitle(prompt) {
                return prompt
            }
        }

        return nil
    }

    private static func valueAfterMarker(_ marker: String, in text: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let start = markerRange.upperBound
        let tail = text[start...]
        let terminators = [
            "\"]",
            "\",\"last-assistant-message",
            "\n\n"
        ]

        let end = terminators
            .compactMap { tail.range(of: $0)?.lowerBound }
            .min() ?? tail.endIndex
        let raw = String(tail[..<end])
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unescaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\\n"#, with: "\n")
            .replacingOccurrences(of: #"\\/"#, with: "/")
    }

    private static func isUsefulTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && trimmed.count <= 80
            && !trimmed.contains("Generate a concise")
            && !trimmed.contains("You are a helpful assistant")
    }

    private static func value(after flag: String, in text: String, allowsSpaces: Bool = false) -> String? {
        let flagCandidates = ["\(flag)=", flag]
        guard let flagRange = flagCandidates.compactMap({ candidate -> Range<String.Index>? in
            text.range(of: candidate)
        }).min(by: { $0.lowerBound < $1.lowerBound }) else {
            return nil
        }

        var valueStart = flagRange.upperBound
        if text[flagRange].hasSuffix(flag) {
            while valueStart < text.endIndex, text[valueStart].isWhitespace {
                valueStart = text.index(after: valueStart)
            }
        }

        guard valueStart < text.endIndex else { return nil }

        let tail = text[valueStart...]
        let valueEnd: String.Index
        if tail.first == "\"" || tail.first == "'" {
            let quote = tail.first!
            let contentStart = text.index(after: valueStart)
            guard let endQuote = text[contentStart...].firstIndex(of: quote) else { return nil }
            return String(text[contentStart..<endQuote])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if allowsSpaces {
            valueEnd = tail.range(of: #" --[A-Za-z0-9][A-Za-z0-9_-]*"#, options: .regularExpression)?.lowerBound
                ?? text.endIndex
        } else {
            valueEnd = tail.firstIndex(where: \.isWhitespace) ?? text.endIndex
        }

        let value = String(text[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
