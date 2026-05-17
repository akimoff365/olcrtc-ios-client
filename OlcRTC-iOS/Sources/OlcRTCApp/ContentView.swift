import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var proxy: LocalProxyController
    @State private var importText = ""
    @State private var importError: String?
    @State private var importMessage: String?
    @State private var isImporting = false
    @State private var copiedProxy: ProxyCopyKind?
    @State private var copiedLogs = false
    @State private var isRefreshing = false
    @State private var toastMessage: ToastMessage?
    @FocusState private var importFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppHeader()

                    ConnectionPanel(
                        status: proxy.status,
                        networkName: proxy.networkName,
                        activeProfile: proxy.activeProfile,
                        healthState: proxy.healthState,
                        reconnectCount: proxy.reconnectCount,
                        lastMessage: proxy.lastMessage,
                        restart: {
                            hapticFeedback(.medium)
                            proxy.restartSocks()
                        },
                        stop: {
                            hapticFeedback(.heavy)
                            proxy.stop()
                        },
                        canRestart: proxy.canRestart,
                        canStop: proxy.status != .stopped
                    )

                    ImportPanel(
                        importText: $importText,
                        importError: importError,
                        importMessage: importMessage,
                        isImporting: isImporting,
                        importFocused: $importFocused,
                        paste: pasteProfile,
                        submit: { importProfile(from: importText) }
                    )

                    ProfilesPanel(
                        profiles: store.profiles,
                        activeProfile: proxy.activeProfile,
                        isBusy: proxy.status == .starting || proxy.status == .restarting,
                        connect: { profile in
                            hapticFeedback(.medium)
                            Task {
                                await proxy.start(profile: profile)
                            }
                        },
                        remove: { profile in
                            hapticFeedback(.light)
                            store.remove(profile)
                            showToast("Профиль удалён", type: .info)
                        }
                    )

                    ProxyPanel(
                        port: proxy.socksPort,
                        credentials: proxy.credentials,
                        copied: copiedProxy,
                        copySocksLink: copySocksLink,
                        copySocks5Link: copySocks5Link,
                        copySettings: copyProxySettings
                    )

                    DiagnosticsPanel(
                        logs: proxy.logs,
                        copied: copiedLogs,
                        copy: copyLogs
                    )
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await refreshStatus()
            }
            .navigationTitle("Gateway")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        hapticFeedback(.medium)
                        proxy.restartSocks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!proxy.canRestart)

                    Button(role: .destructive) {
                        hapticFeedback(.heavy)
                        proxy.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(proxy.status == .stopped)
                }
            }
            .onOpenURL { url in
                importProfile(from: url.absoluteString)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    proxy.appDidBecomeActive()
                }
            }
            .overlay(alignment: .top) {
                if let toast = toastMessage {
                    ToastView(message: toast.text, type: toast.type)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1000)
                        .padding(.top, 60)
                }
            }
        }
    }
    
    private func refreshStatus() async {
        isRefreshing = true
        hapticFeedback(.light)
        try? await Task.sleep(for: .seconds(0.5))
        proxy.appDidBecomeActive()
        isRefreshing = false
    }
    
    private func showToast(_ text: String, type: ToastType) {
        toastMessage = ToastMessage(text: text, type: type)
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation {
                toastMessage = nil
            }
        }
    }
    
    private func hapticFeedback(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
        #endif
    }

    private func pasteProfile() {
        #if canImport(UIKit)
        if let value = UIPasteboard.general.string {
            importText = value
            importError = nil
            importMessage = nil
            hapticFeedback(.light)
            showToast("Вставлено из буфера", type: .success)
        }
        #endif
    }

    private func importProfile(from rawValue: String) {
        guard !isImporting else {
            return
        }

        Task {
            await MainActor.run {
                isImporting = true
                importError = nil
                importMessage = nil
                importFocused = false
            }

            do {
                let result = try await SubscriptionImporter.importValue(rawValue)
                await MainActor.run {
                    store.upsert(result.profiles)
                    importText = ""
                    importMessage = result.userMessage
                    isImporting = false
                    hapticFeedback(.medium)
                    showToast("Профили импортированы", type: .success)
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                    hapticFeedback(.heavy)
                    showToast("Ошибка импорта", type: .error)
                }
            }
        }
    }

    private func copyProxySettings() {
        #if canImport(UIKit)
        UIPasteboard.general.string = """
        SOCKS5
        Host: 127.0.0.1
        Port: \(proxy.socksPort)
        Username: \(proxy.credentials.username)
        Password: \(proxy.credentials.password)
        """
        markCopied(.settings)
        hapticFeedback(.light)
        showToast("Настройки скопированы", type: .success)
        #endif
    }

    private func copySocksLink() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.credentials.legacySocksURL(port: proxy.socksPort)
        markCopied(.socks)
        hapticFeedback(.light)
        showToast("socks:// скопирован", type: .success)
        #endif
    }

    private func copySocks5Link() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.credentials.socks5URL(port: proxy.socksPort)
        markCopied(.socks5)
        hapticFeedback(.light)
        showToast("socks5:// скопирован", type: .success)
        #endif
    }

    private func copyLogs() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.logText
        copiedLogs = true
        hapticFeedback(.light)
        showToast("Лог скопирован", type: .success)
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedLogs = false
        }
        #endif
    }

    private func markCopied(_ kind: ProxyCopyKind) {
        copiedProxy = kind
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedProxy == kind {
                copiedProxy = nil
            }
        }
    }
}

private struct ConnectionPanel: View {
    let status: LocalProxyController.Status
    let networkName: String
    let activeProfile: OlcRTCProfile?
    let healthState: LocalProxyController.HealthState
    let reconnectCount: Int
    let lastMessage: String?
    let restart: () -> Void
    let stop: () -> Void
    let canRestart: Bool
    let canStop: Bool
    
    @State private var pulseAnimation = false

    var body: some View {
        Panel(title: "Подключение", systemImage: status.symbolName) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatusBadge(status: status)
                    Spacer()
                    NetworkBadge(name: networkName)
                }

                ZStack {
                    // Пульсирующий эффект для активного соединения
                    if status == .running {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [status.tint.opacity(0.3), status.tint.opacity(0)],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 72
                                )
                            )
                            .frame(width: 132, height: 132)
                            .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                            .opacity(pulseAnimation ? 0 : 1)
                            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: pulseAnimation)
                    }
                    
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [status.tint.opacity(0.18), status.tint.opacity(0.04)],
                                center: .center,
                                startRadius: 4,
                                endRadius: 72
                            )
                        )
                        .frame(width: 132, height: 132)
                    
                    Circle()
                        .stroke(status.tint.opacity(0.28), lineWidth: 2)
                        .frame(width: 94, height: 94)
                    
                    Image(systemName: status.symbolName)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [status.tint, status.tint.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.bounce, value: status)
                }
                .frame(maxWidth: .infinity)
                .onAppear {
                    if status == .running {
                        pulseAnimation = true
                    }
                }
                .onChange(of: status) { _, newStatus in
                    pulseAnimation = newStatus == .running
                }

                VStack(spacing: 5) {
                    Text(status.rawValue)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(status.tint)
                    Text(activeProfile?.displayName ?? "Выбери профиль ниже")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let activeProfile {
                        Text("\(activeProfile.carrierDisplayName) / \(activeProfile.transportDisplayName)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: restart) {
                        Label("Перезапустить", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.tint)
                    .controlSize(.large)
                    .disabled(!canRestart)
                    .animation(.spring(response: 0.3), value: canRestart)

                    Button(role: .destructive, action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 44, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canStop)
                    .animation(.spring(response: 0.3), value: canStop)
                }

                HStack(spacing: 10) {
                    MetricView(title: "Маршрут", value: healthState.rawValue)
                    MetricView(title: "Рестарты", value: "\(reconnectCount)")
                    MetricView(title: "Auth", value: "On")
                }

                if let lastMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text(lastMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

private struct AppHeader: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("OlcRTC Gateway")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("Локальный SOCKS-мост для внешнего VPN-клиента")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

private struct ImportPanel: View {
    @Binding var importText: String
    let importError: String?
    let importMessage: String?
    let isImporting: Bool
    var importFocused: FocusState<Bool>.Binding
    let paste: () -> Void
    let submit: () -> Void

    var body: some View {
        Panel(title: "Импорт профиля", systemImage: "link.badge.plus") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("olcrtc://, https://subscription или sub.md", text: $importText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused(importFocused)
                    .lineLimit(4...8)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemGroupedBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(importFocused.wrappedValue ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: importFocused.wrappedValue)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Button("Cancel") {
                                importFocused.wrappedValue = false
                            }
                            Spacer()
                            Button("Done") {
                                importFocused.wrappedValue = false
                            }
                            .fontWeight(.semibold)
                        }
                    }

                HStack(spacing: 10) {
                    Button(action: paste) {
                        Label("Вставить", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: submit) {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Загрузка")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Импорт", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isImporting || importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let importError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(importError)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
                    .transition(.scale.combined(with: .opacity))
                } else if let importMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(importMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                    )
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}

private struct ProfilesPanel: View {
    let profiles: [OlcRTCProfile]
    let activeProfile: OlcRTCProfile?
    let isBusy: Bool
    let connect: (OlcRTCProfile) -> Void
    let remove: (OlcRTCProfile) -> Void

    var body: some View {
        Panel(title: "Профили", systemImage: "rectangle.stack.fill") {
            if profiles.isEmpty {
                ContentUnavailableView("Профилей нет", systemImage: "link")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 10) {
                    HStack {
                        Label("\(profiles.count) профилей", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ForEach(profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: activeProfile?.id == profile.id,
                            isBusy: isBusy,
                            connect: { connect(profile) },
                            remove: { remove(profile) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                remove(profile)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                connect(profile)
                            } label: {
                                Label("Подключить", systemImage: "power")
                            }
                            .tint(.green)
                        }
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: profiles.count)
            }
        }
    }
}

private struct ProfileRow: View {
    let profile: OlcRTCProfile
    let isActive: Bool
    let isBusy: Bool
    let connect: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                    .frame(width: 36, height: 36)
                
                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(
                        isActive ? 
                        LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .top, endPoint: .bottom) :
                        LinearGradient(colors: [.secondary], startPoint: .top, endPoint: .bottom)
                    )
                    .symbolEffect(.bounce, value: isActive)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MiniPill(text: profile.carrierDisplayName)
                    MiniPill(text: profile.transportDisplayName)
                    MiniPill(text: profile.compatibilityLabel)
                }
                Text("\(profile.roomLabel) / \(profile.clientID)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: connect) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            Button(role: .destructive, action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: isActive ? .green.opacity(0.2) : .clear, radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .animation(.spring(response: 0.3), value: isActive)
    }
}

private struct MiniPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }
}

private struct ProxyPanel: View {
    let port: Int
    let credentials: SocksCredentials
    let copied: ProxyCopyKind?
    let copySocksLink: () -> Void
    let copySocks5Link: () -> Void
    let copySettings: () -> Void

    var body: some View {
        Panel(title: "Локальный прокси", systemImage: "network") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    ProxyInfoRow(label: "Type", value: "SOCKS5", icon: "network")
                    ProxyInfoRow(label: "Host", value: "127.0.0.1", icon: "server.rack")
                    ProxyInfoRow(label: "Port", value: "\(port)", icon: "number")
                    ProxyInfoRow(label: "Auth", value: "On", icon: "lock.fill")
                    ProxyInfoRow(label: "User", value: credentials.username, icon: "person.fill")
                    ProxyInfoRow(label: "Pass", value: credentials.password, icon: "key.fill")
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                HStack(spacing: 10) {
                    Button(action: copySocksLink) {
                        Label(copied == .socks ? "Скопировано" : "socks://", systemImage: copied == .socks ? "checkmark" : "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .animation(.spring(response: 0.3), value: copied)

                    Button(action: copySocks5Link) {
                        Label(copied == .socks5 ? "Скопировано" : "socks5://", systemImage: copied == .socks5 ? "checkmark" : "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .animation(.spring(response: 0.3), value: copied)
                }

                Button(action: copySettings) {
                    Label(copied == .settings ? "Скопировано" : "Копировать вручную", systemImage: copied == .settings ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .animation(.spring(response: 0.3), value: copied)

                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.orange)
                    Text("Сначала запусти профиль здесь, затем включи SOCKS-профиль во внешнем клиенте. После смены сети выключи внешний туннель, перезапусти SOCKS и включи туннель снова.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
    }
}

private struct ProxyInfoRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(value)
                .font(.callout.monospaced().weight(.medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

private struct DiagnosticsPanel: View {
    let logs: [ProxyLogEntry]
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        Panel(title: "Диагностика", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Последние события", systemImage: "clock.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: copy) {
                        Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(logs.isEmpty)
                    .animation(.spring(response: 0.3), value: copied)
                }

                if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.tertiary)
                        Text("Лог пуст")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(logs.prefix(12))) { entry in
                            LogRow(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: ProxyLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(entry.level.tint.opacity(0.15))
                    .frame(width: 24, height: 24)
                
                Image(systemName: entry.level.symbolName)
                    .font(.caption)
                    .foregroundStyle(entry.level.tint)
            }

            Text(entry.line)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(entry.level.tint.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct Panel<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.primary, .primary.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
    }
}

private struct StatusBadge: View {
    let status: LocalProxyController.Status
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if status == .running {
                    Circle()
                        .fill(status.tint.opacity(0.3))
                        .frame(width: 10, height: 10)
                        .scaleEffect(isAnimating ? 1.8 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                }
                
                Circle()
                    .fill(status.tint)
                    .frame(width: 10, height: 10)
            }
            .onAppear {
                if status == .running {
                    withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        isAnimating = true
                    }
                }
            }
            .onChange(of: status) { _, newStatus in
                isAnimating = newStatus == .running
            }
            
            Text(status.rawValue)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(status.tint.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(status.tint.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

private struct NetworkBadge: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "antenna.radiowaves.left.and.right")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
            .symbolEffect(.variableColor.iterative, options: .repeating)
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        )
    }
}

private extension ProxyLogEntry.Level {
    var tint: Color {
        switch self {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private extension LocalProxyController.Status {
    var tint: Color {
        switch self {
        case .running:
            return .green
        case .starting, .restarting, .needsTunnelRestart:
            return .orange
        case .failed:
            return .red
        case .stopped:
            return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .running:
            return "checkmark.shield.fill"
        case .starting:
            return "hourglass"
        case .restarting:
            return "arrow.triangle.2.circlepath"
        case .needsTunnelRestart:
            return "exclamationmark.arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "power"
        }
    }
}

private enum ProxyCopyKind: Equatable {
    case socks
    case socks5
    case settings
}

// MARK: - Toast System

private struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let type: ToastType
}

private enum ToastType {
    case success
    case error
    case info
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

private struct ToastView: View {
    let message: String
    let type: ToastType
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundStyle(type.color)
            
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
}
