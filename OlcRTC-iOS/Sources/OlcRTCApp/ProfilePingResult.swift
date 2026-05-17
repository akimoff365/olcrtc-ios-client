import Foundation

struct ProfilePingResult: Equatable {
    enum State: Equatable {
        case idle
        case checking
        case success(TimeInterval)
        case failed(String)

        var isChecking: Bool {
            if case .checking = self {
                return true
            }
            return false
        }
    }

    let state: State
    let checkedAt: Date?

    static let idle = ProfilePingResult(state: .idle, checkedAt: nil)
}
