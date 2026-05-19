import Foundation

struct SubscriptionImportResult: Sendable {
    let profiles: [OlcRTCProfile]
    let title: String

    var userMessage: String {
        if profiles.count == 1 {
            return "Импортирован профиль: \(profiles[0].displayName)"
        }
        return "Импортировано профилей: \(profiles.count) из \(title)"
    }
}

enum SubscriptionImportError: LocalizedError {
    case emptyInput
    case noProfiles
    case badHTTPStatus(Int)
    case bodyTooLarge(Int)
    case nonUTF8Body
    case invalidServer(line: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Вставь olcrtc:// ссылку, URL подписки или текст подписки."
        case .noProfiles:
            return "В подписке не найдено olcrtc:// профилей."
        case let .badHTTPStatus(status):
            return "Сервер подписки вернул HTTP \(status)."
        case let .bodyTooLarge(limit):
            return "Подписка слишком большая. Лимит: \(limit / 1024) KB."
        case .nonUTF8Body:
            return "Подписка не похожа на UTF-8 текст."
        case let .invalidServer(line, reason):
            return "Ошибка профиля в строке \(line): \(reason)"
        }
    }
}

enum SubscriptionImporter {
    private static let subscriptionTimeout: TimeInterval = 15
    private static let maxSubscriptionBytes = 512 * 1024

    static func importValue(_ rawValue: String) async throws -> SubscriptionImportResult {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw SubscriptionImportError.emptyInput
        }

        if let url = subscriptionURL(from: value) {
            let content = try await fetchSubscription(from: url)
            return try parseSubscription(content, fallbackTitle: url.host(percentEncoded: false) ?? "subscription")
        }

        if value.lowercased().hasPrefix("olcrtc://"), !value.contains("\n") {
            let profile = try OlcRTCProfile(uri: value)
            return SubscriptionImportResult(profiles: [profile], title: profile.displayName)
        }

        return try parseSubscription(value, fallbackTitle: "clipboard")
    }

    static func parseSubscription(_ rawValue: String, fallbackTitle: String = "subscription") throws -> SubscriptionImportResult {
        var title = fallbackTitle
        var parsedServers: [ParsedServer] = []
        var currentServerIndex: Int?

        for (offset, rawLine) in rawValue.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            if line.lowercased().hasPrefix("olcrtc://") {
                parsedServers.append(ParsedServer(uri: line, fields: [:], lineNumber: lineNumber))
                currentServerIndex = parsedServers.count - 1
                continue
            }

            if line.hasPrefix("##") {
                guard let currentServerIndex, let field = parseField(String(line.dropFirst(2))) else {
                    continue
                }
                parsedServers[currentServerIndex].fields[field.key] = field.value
                continue
            }

            if line.hasPrefix("#"), let field = parseField(String(line.dropFirst())) {
                if field.key == "name", !field.value.isEmpty {
                    title = field.value
                }
            }
        }

        guard !parsedServers.isEmpty else {
            throw SubscriptionImportError.noProfiles
        }

        let profiles = try parsedServers.enumerated().map { index, server in
            do {
                let profile = try OlcRTCProfile(uri: server.uri)
                let name = normalized(server.fields["name"])
                    ?? normalized(server.fields["comment"])
                    ?? normalized(profile.comment)
                    ?? "Профиль \(index + 1)"
                return profile.renamed(name)
            } catch {
                throw SubscriptionImportError.invalidServer(line: server.lineNumber, reason: error.localizedDescription)
            }
        }

        return SubscriptionImportResult(profiles: profiles, title: title)
    }

    private static func subscriptionURL(from value: String) -> URL? {
        guard !value.contains("\n"), !value.lowercased().hasPrefix("olcrtc://") else {
            return nil
        }

        if let url = URL(string: value),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host(percentEncoded: false) != nil {
            return url
        }

        guard value.contains("."),
              !value.contains(" "),
              let url = URL(string: "https://\(value)"),
              url.host(percentEncoded: false) != nil else {
            return nil
        }
        return url
    }

    private static func fetchSubscription(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = subscriptionTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/plain, text/markdown, */*", forHTTPHeaderField: "Accept")
        request.setValue("OlcRTC-iOS/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            throw SubscriptionImportError.badHTTPStatus(response.statusCode)
        }

        guard data.count <= maxSubscriptionBytes else {
            throw SubscriptionImportError.bodyTooLarge(maxSubscriptionBytes)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw SubscriptionImportError.nonUTF8Body
        }
        return content
    }

    private static func parseField(_ value: String) -> (key: String, value: String)? {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return nil
        }

        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return nil
        }
        return (key, value)
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ParsedServer {
    var uri: String
    var fields: [String: String]
    var lineNumber: Int
}
