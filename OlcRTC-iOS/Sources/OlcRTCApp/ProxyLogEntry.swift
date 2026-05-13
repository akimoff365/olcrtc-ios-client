import Foundation

struct ProxyLogEntry: Identifiable, Equatable {
    enum Level: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }

    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    var line: String {
        "\(Self.formatter.string(from: date)) [\(level.rawValue)] \(message)"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
