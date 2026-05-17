import Foundation

enum ReadinessState: String {
    case notReady = "Не готов"
    case checking = "Проверка"
    case ready = "Готов"
    case readyWithIssues = "Готов с замечаниями"
    
    var color: String {
        switch self {
        case .notReady: return "red"
        case .checking: return "yellow"
        case .ready: return "green"
        case .readyWithIssues: return "orange"
        }
    }
    
    var icon: String {
        switch self {
        case .notReady: return "xmark.circle.fill"
        case .checking: return "hourglass"
        case .ready: return "checkmark.circle.fill"
        case .readyWithIssues: return "exclamationmark.triangle.fill"
        }
    }
    
    var message: String {
        switch self {
        case .notReady:
            return "Запустите профиль для подключения"
        case .checking:
            return "Проверяем готовность системы..."
        case .ready:
            return "Всё готово! Можно включать внешний VPN"
        case .readyWithIssues:
            return "Работает, но есть проблемы"
        }
    }
}

struct ReadinessCheck: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let message: String?
    
    var icon: String {
        passed ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    
    var color: String {
        passed ? "green" : "red"
    }
}

@MainActor
class ReadinessChecker {
    static func check(
        status: LocalProxyController.Status,
        healthState: LocalProxyController.HealthState,
        socksPort: Int,
        credentials: SocksCredentials
    ) async -> (state: ReadinessState, checks: [ReadinessCheck]) {
        
        var checks: [ReadinessCheck] = []
        
        // Check 1: SOCKS is running
        let socksRunning = status == .running
        checks.append(ReadinessCheck(
            name: "SOCKS прокси запущен",
            passed: socksRunning,
            message: socksRunning ? "Порт \(socksPort)" : "Запустите профиль"
        ))
        
        guard socksRunning else {
            return (.notReady, checks)
        }
        
        // Check 2: Health state
        let isHealthy = healthState == .healthy
        checks.append(ReadinessCheck(
            name: "Проверка здоровья",
            passed: isHealthy,
            message: isHealthy ? "Маршрут работает" : "Маршрут не проверен"
        ))
        
        // Check 3: SOCKS connectivity
        let socksWorks = await OlcRTCEngine.checkLocalSocks(
            port: socksPort,
            credentials: credentials,
            timeoutNanoseconds: 3_000_000_000
        )
        checks.append(ReadinessCheck(
            name: "SOCKS аутентификация",
            passed: socksWorks,
            message: socksWorks ? "Авторизация работает" : "Не удалось подключиться"
        ))
        
        // Check 4: Tunnel connectivity
        let tunnelWorks = await OlcRTCEngine.checkTunnelConnectivity(
            port: socksPort,
            credentials: credentials,
            timeoutNanoseconds: 8_000_000_000
        )
        checks.append(ReadinessCheck(
            name: "Туннель работает",
            passed: tunnelWorks,
            message: tunnelWorks ? "CONNECT успешен" : "Туннель не отвечает"
        ))
        
        // Determine overall state
        let allPassed = checks.allSatisfy { $0.passed }
        let somePassed = checks.contains { $0.passed }
        
        if allPassed {
            return (.ready, checks)
        } else if somePassed {
            return (.readyWithIssues, checks)
        } else {
            return (.notReady, checks)
        }
    }
}
