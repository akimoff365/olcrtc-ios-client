# 🔧 План исправлений

## Критические исправления (Priority 1)

### 1. Race Condition Protection
**Проблема:** Параллельные операции start/stop/restart  
**Решение:** Добавить флаг `isOperationInProgress`

```swift
@Published private(set) var isOperationInProgress = false

func start(profile: OlcRTCProfile) async {
    guard !isOperationInProgress else {
        appendLog(.warning, "Operation already in progress, ignoring")
        return
    }
    isOperationInProgress = true
    defer { isOperationInProgress = false }
    // ... existing code
}
```

---

### 2. Network Change Debounce
**Проблема:** Слишком частые реконнекты при нестабильной сети  
**Решение:** Добавить задержку 2.5 секунды

```swift
private var networkChangeTask: Task<Void, Never>?

private func handlePathUpdate(_ snapshot: NetworkPathSnapshot) {
    networkName = snapshot.name
    
    // Cancel previous pending network change
    networkChangeTask?.cancel()
    
    // ... existing signature check ...
    
    // Debounce network changes
    networkChangeTask = Task {
        try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
        guard !Task.isCancelled else { return }
        await processNetworkChange(snapshot)
    }
}

private func processNetworkChange(_ snapshot: NetworkPathSnapshot) async {
    // First, check if connection is actually broken
    let isAlive = await OlcRTCEngine.checkTunnelConnectivity(
        port: socksPort,
        credentials: credentials
    )
    
    if isAlive {
        appendLog(.info, "Network changed but tunnel still works")
        return
    }
    
    // Connection is broken, proceed with recovery
    enterExternalTunnelRecovery("Network changed to \(snapshot.name)")
}
```

---

### 3. Watchdog Conflict Prevention
**Проблема:** Watchdog может запустить рестарт во время ручного рестарта  
**Решение:** Проверять флаг операции

```swift
private func runWatchdogTick() async {
    guard status == .running,
          let activeProfile,
          !isOperationInProgress else {
        return
    }
    // ... rest of code
}
```

---

### 4. Retry Logic on Start
**Проблема:** Нет повторных попыток при временных ошибках  
**Решение:** 3 попытки с экспоненциальным backoff

```swift
func start(profile: OlcRTCProfile) async {
    guard !isOperationInProgress else { return }
    isOperationInProgress = true
    defer { isOperationInProgress = false }
    
    let maxAttempts = 3
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            try await attemptStart(profile: profile, attempt: attempt)
            return // Success!
        } catch {
            lastError = error
            appendLog(.warning, "Start attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
            
            if attempt < maxAttempts {
                let delaySeconds = Double(attempt * attempt) // 1s, 4s
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }
    }
    
    // All attempts failed
    stopEngineInBackground()
    BackgroundKeepAlive.shared.stop()
    activeProfile = nil
    status = .failed
    lastMessage = "Не удалось запустить после \(maxAttempts) попыток: \(lastError?.localizedDescription ?? "unknown")"
    appendLog(.error, "All start attempts failed")
}

private func attemptStart(profile: OlcRTCProfile, attempt: Int) async throws {
    // ... existing start logic ...
}
```

---

## Важные улучшения (Priority 2)

### 5. Increased Timeouts
**Проблема:** 8 секунд может быть мало на медленных сетях  
**Решение:** Увеличить до 12 секунд

```swift
static func checkTunnelConnectivity(
    port: Int,
    credentials: SocksCredentials,
    timeoutNanoseconds: UInt64 = 12_000_000_000  // 12 seconds
) async -> Bool
```

---

### 6. Exponential Backoff for Watchdog
**Проблема:** Фиксированный интервал создаёт нагрузку  
**Решение:** Адаптивный интервал

```swift
private var watchdogInterval: UInt64 = 45_000_000_000 // Start with 45s
private let watchdogMaxInterval: UInt64 = 300_000_000_000 // Max 5 minutes

private func runWatchdogTick() async {
    // ... existing checks ...
    
    if isAlive {
        // Reset interval on success
        watchdogInterval = 45_000_000_000
    } else {
        // Increase interval on failure
        watchdogInterval = min(watchdogInterval * 2, watchdogMaxInterval)
        appendLog(.info, "Watchdog interval increased to \(watchdogInterval / 1_000_000_000)s")
    }
}
```

---

### 7. Background State Handling
**Проблема:** Нет обработки фоновых ограничений  
**Решение:** Снижать активность в фоне

```swift
private var isInBackground = false

func appWillResignActive() {
    isInBackground = true
    // Increase watchdog interval in background
    if status == .running {
        stopWatchdog()
        startWatchdog(interval: 120_000_000_000) // 2 minutes in background
    }
}

func appDidBecomeActive() {
    isInBackground = false
    // Restore normal watchdog interval
    if status == .running {
        stopWatchdog()
        startWatchdog(interval: 45_000_000_000) // 45 seconds in foreground
    }
    // ... existing foreground check ...
}
```

---

### 8. Parallel SOCKS Checks
**Проблема:** Последовательная проверка медленная  
**Решение:** Параллельная проверка

```swift
static func checkTunnelConnectivity(...) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        // Add timeout task
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return false
        }
        
        // Add parallel probe tasks
        for target in SocksConnectTarget.defaults {
            group.addTask {
                await Self.socksConnectProbe(
                    port: port,
                    credentials: credentials,
                    target: target
                )
            }
        }
        
        // Return on first success
        for await result in group {
            if result {
                group.cancelAll()
                return true
            }
        }
        
        return false
    }
}
```

---

## Дополнительные улучшения (Priority 3)

### 9. Persistent Port Preference
**Решение:** Сохранять последний успешный порт

```swift
private let portStorageKey = "olcrtc.last.successful.port"

private func saveSuccessfulPort(_ port: Int) {
    UserDefaults.standard.set(port, forKey: portStorageKey)
}

private func loadPreferredPort() -> Int {
    let saved = UserDefaults.standard.integer(forKey: portStorageKey)
    return saved > 0 ? saved : 18080
}

// Use in start:
let requestedPort = loadPreferredPort()
// ... after successful start ...
saveSuccessfulPort(startResult.port)
```

---

### 10. Structured Logging
**Решение:** Добавить контекст в логи

```swift
private func appendLog(_ level: ProxyLogEntry.Level, _ message: String, context: [String: String] = [:]) {
    var fullMessage = message
    if !context.isEmpty {
        let contextStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        fullMessage += " [\(contextStr)]"
    }
    
    logs.insert(ProxyLogEntry(date: Date(), level: level, message: fullMessage), at: 0)
    if logs.count > 200 { // Increased from 160
        logs.removeLast(logs.count - 200)
    }
}

// Usage:
appendLog(.info, "Starting profile", context: [
    "profile": profile.displayName,
    "port": "\(socksPort)",
    "network": networkName
])
```

---

### 11. Graceful Shutdown
**Решение:** Дождаться завершения

```swift
func stop() async {
    guard !isOperationInProgress else { return }
    isOperationInProgress = true
    defer { isOperationInProgress = false }
    
    reconnectTask?.cancel()
    reconnectTask = nil
    foregroundCheckTask?.cancel()
    foregroundCheckTask = nil
    networkChangeTask?.cancel()
    networkChangeTask = nil
    stopWatchdog()
    
    // Wait for engine to stop
    await Task.detached(priority: .utility) {
        OlcRTCEngine.stop()
    }.value
    
    BackgroundKeepAlive.shared.stop()
    
    activeProfile = nil
    reconnectCount = 0
    networkName = "Нет"
    healthState = .idle
    consecutiveHealthFailures = 0
    lastPathSignature = nil
    stopPathMonitor()
    status = .stopped
    lastMessage = nil
    appendLog(.info, "Stopped gracefully")
}
```

---

## Метрики и мониторинг (Priority 4)

### 12. Connection Metrics
**Решение:** Отслеживать статистику

```swift
struct ConnectionMetrics {
    var totalReconnects = 0
    var networkChanges = 0
    var watchdogRestarts = 0
    var manualRestarts = 0
    var lastSuccessfulStart: Date?
    var uptimeSeconds: TimeInterval = 0
    var averageTimeBetweenReconnects: TimeInterval = 0
}

@Published private(set) var metrics = ConnectionMetrics()

private func updateMetrics(event: MetricEvent) {
    switch event {
    case .reconnect:
        metrics.totalReconnects += 1
    case .networkChange:
        metrics.networkChanges += 1
    case .watchdogRestart:
        metrics.watchdogRestarts += 1
    case .manualRestart:
        metrics.manualRestarts += 1
    case .successfulStart:
        metrics.lastSuccessfulStart = Date()
    }
}
```

---

## Тестирование

### Unit Tests
```swift
// Test race condition protection
func testConcurrentStartCalls() async {
    let controller = LocalProxyController()
    let profile = makeTestProfile()
    
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                await controller.start(profile: profile)
            }
        }
    }
    
    // Should only start once
    XCTAssertEqual(controller.reconnectCount, 0)
}

// Test network debounce
func testNetworkChangeDebounce() async {
    let controller = LocalProxyController()
    
    // Simulate rapid network changes
    for _ in 0..<5 {
        controller.simulateNetworkChange()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
    }
    
    // Should only trigger one reconnect
    XCTAssertLessThanOrEqual(controller.reconnectCount, 1)
}
```

---

## Чеклист внедрения

- [ ] 1. Race condition protection
- [ ] 2. Network debounce
- [ ] 3. Watchdog conflict prevention
- [ ] 4. Retry logic
- [ ] 5. Increased timeouts
- [ ] 6. Exponential backoff
- [ ] 7. Background handling
- [ ] 8. Parallel SOCKS checks
- [ ] 9. Port persistence
- [ ] 10. Structured logging
- [ ] 11. Graceful shutdown
- [ ] 12. Metrics tracking
- [ ] 13. Unit tests
- [ ] 14. Integration tests
- [ ] 15. Beta testing

---

**Готов начать внедрение?** Начнём с критических исправлений (1-4)?
