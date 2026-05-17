import Foundation

struct ConnectionMetrics: Codable {
    // Counters
    var totalReconnects: Int = 0
    var networkChanges: Int = 0
    var watchdogRestarts: Int = 0
    var manualRestarts: Int = 0
    var successfulStarts: Int = 0
    var failedStarts: Int = 0
    
    // Timing
    var totalUptime: TimeInterval = 0
    var lastSessionStart: Date?
    var lastSuccessfulConnection: Date?
    var longestSession: TimeInterval = 0
    var averageSessionDuration: TimeInterval = 0
    
    // Network analysis
    var networkTypeUsage: [String: TimeInterval] = [:] // "Wi-Fi": 3600, "LTE": 1200
    var reconnectsByHour: [Int: Int] = [:] // Hour: count
    var failureReasons: [String: Int] = [:] // Reason: count
    
    // Health
    var consecutiveSuccesses: Int = 0
    var consecutiveFailures: Int = 0
    var healthScore: Double = 100.0 // 0-100
    
    // Session history (last 100 sessions)
    var sessionHistory: [SessionRecord] = []
    
    mutating func recordEvent(_ event: MetricEvent) {
        switch event {
        case .reconnect(let reason):
            totalReconnects += 1
            failureReasons[reason, default: 0] += 1
            consecutiveSuccesses = 0
            consecutiveFailures += 1
            updateHealthScore()
            
        case .networkChange(let from, let to):
            networkChanges += 1
            addSessionHistory(event: "Network: \(from) → \(to)")
            
        case .watchdogRestart:
            watchdogRestarts += 1
            addSessionHistory(event: "Watchdog restart")
            
        case .manualRestart:
            manualRestarts += 1
            addSessionHistory(event: "Manual restart")
            
        case .successfulStart:
            successfulStarts += 1
            lastSuccessfulConnection = Date()
            consecutiveFailures = 0
            consecutiveSuccesses += 1
            updateHealthScore()
            startNewSession()
            
        case .failedStart(let reason):
            failedStarts += 1
            failureReasons[reason, default: 0] += 1
            consecutiveSuccesses = 0
            consecutiveFailures += 1
            updateHealthScore()
            
        case .sessionEnd(let duration):
            endCurrentSession(duration: duration)
            
        case .networkUsage(let type, let duration):
            networkTypeUsage[type, default: 0] += duration
        }
    }
    
    private mutating func startNewSession() {
        lastSessionStart = Date()
    }
    
    private mutating func endCurrentSession(duration: TimeInterval) {
        totalUptime += duration
        
        if duration > longestSession {
            longestSession = duration
        }
        
        // Update average
        let totalSessions = sessionHistory.count + 1
        averageSessionDuration = (averageSessionDuration * Double(sessionHistory.count) + duration) / Double(totalSessions)
        
        // Record by hour
        let hour = Calendar.current.component(.hour, from: Date())
        reconnectsByHour[hour, default: 0] += 1
    }
    
    private mutating func addSessionHistory(event: String) {
        let record = SessionRecord(date: Date(), event: event)
        sessionHistory.insert(record, at: 0)
        
        if sessionHistory.count > 100 {
            sessionHistory.removeLast()
        }
    }
    
    private mutating func updateHealthScore() {
        // Health score based on success/failure ratio
        let totalAttempts = consecutiveSuccesses + consecutiveFailures
        guard totalAttempts > 0 else { return }
        
        let successRate = Double(consecutiveSuccesses) / Double(totalAttempts)
        healthScore = successRate * 100.0
        
        // Decay over time if no activity
        if let lastConnection = lastSuccessfulConnection {
            let hoursSinceLastSuccess = Date().timeIntervalSince(lastConnection) / 3600
            if hoursSinceLastSuccess > 24 {
                healthScore *= 0.9 // 10% penalty per day
            }
        }
        
        healthScore = max(0, min(100, healthScore))
    }
    
    // Computed properties
    var successRate: Double {
        let total = successfulStarts + failedStarts
        guard total > 0 else { return 0 }
        return Double(successfulStarts) / Double(total) * 100
    }
    
    var averageReconnectsPerDay: Double {
        guard let firstSession = sessionHistory.last?.date else { return 0 }
        let days = Date().timeIntervalSince(firstSession) / 86400
        guard days > 0 else { return 0 }
        return Double(totalReconnects) / days
    }
    
    var mostProblematicNetwork: String? {
        reconnectsByHour.max(by: { $0.value < $1.value })?.key.description
    }
    
    var formattedTotalUptime: String {
        let hours = Int(totalUptime) / 3600
        let minutes = (Int(totalUptime) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    var formattedAverageSession: String {
        let minutes = Int(averageSessionDuration) / 60
        let seconds = Int(averageSessionDuration) % 60
        return "\(minutes)m \(seconds)s"
    }
    
    var formattedLongestSession: String {
        let hours = Int(longestSession) / 3600
        let minutes = (Int(longestSession) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
    
    // Storage
    private static let storageKey = "olcrtc.metrics"
    
    static func load() -> ConnectionMetrics {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let metrics = try? JSONDecoder().decode(ConnectionMetrics.self, from: data) else {
            return ConnectionMetrics()
        }
        return metrics
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    
    mutating func reset() {
        self = ConnectionMetrics()
        save()
    }
}

struct SessionRecord: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let event: String
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum MetricEvent {
    case reconnect(reason: String)
    case networkChange(from: String, to: String)
    case watchdogRestart
    case manualRestart
    case successfulStart
    case failedStart(reason: String)
    case sessionEnd(duration: TimeInterval)
    case networkUsage(type: String, duration: TimeInterval)
}
