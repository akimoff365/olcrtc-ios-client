import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var proxy: LocalProxyController
    @State private var importText = ""
    @State private var importError: String?
    @State private var copiedProxy: ProxyCopyKind?
    @State private var copiedLogs = false
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
                        restart: proxy.restartSocks,
                        stop: proxy.stop,
                        canRestart: proxy.canRestart,
                        canStop: proxy.status != .stopped
                    )

                    ImportPanel(
                        importText: $importText,
                        importError: importError,
                        importFocused: $importFocused,
                        paste: pasteProfile,
                        submit: { importProfile(from: importText) }
                    )

                    ProfilesPanel(
                        profiles: store.profiles,
                        activeProfile: proxy.activeProfile,
                        isBusy: proxy.status == .starting || proxy.status == .restarting,
                        connect: { profile in
                            Task {
                                await proxy.start(profile: profile)
                            }
                        },
                        remove: store.remove
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
            .navigationTitle("OlcRTC")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        proxy.restartSocks()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!proxy.canRestart)

                    Button(role: .destructive) {
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
        }
    }

    private func pasteProfile() {
        #if canImport(UIKit)
        if let value = UIPasteboard.general.string {
            importText = value
        }
        #endif
    }

    private func importProfile(from rawValue: String) {
        do {
            let profile = try OlcRTCProfile(uri: rawValue)
            store.upsert(profile)
            importText = ""
            importError = nil
            importFocused = false
        } catch {
            importError = error.localizedDescription
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
        #endif
    }

    private func copySocksLink() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.credentials.legacySocksURL(port: proxy.socksPort)
        markCopied(.socks)
        #endif
    }

    private func copySocks5Link() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.credentials.socks5URL(port: proxy.socksPort)
        markCopied(.socks5)
        #endif
    }

    private func copyLogs() {
        #if canImport(UIKit)
        UIPasteboard.general.string = proxy.logText
        copiedLogs = true
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

    var body: some View {
        Panel(title: "Gateway", systemImage: status.symbolName) {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    StatusBadge(status: status)
                    Spacer()
                    NetworkBadge(name: networkName)
                }

                ZStack {
                    Circle()
                        .fill(status.tint.opacity(0.12))
                        .frame(width: 124, height: 124)
                    Circle()
                        .stroke(status.tint.opacity(0.28), lineWidth: 2)
                        .frame(width: 94, height: 94)
                    Image(systemName: status.symbolName)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(status.tint)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 5) {
                    Text(status.rawValue)
                        .font(.title2.weight(.bold))
                    Text(activeProfile?.displayName ?? "Выбери профиль ниже")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let activeProfile {
                        Text("\(activeProfile.carrier) / \(activeProfile.transport)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    Button(action: restart) {
                        Label("Restart SOCKS", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canRestart)

                    Button(role: .destructive, action: stop) {
                        Image(systemName: "stop.fill")
                            .frame(width: 42, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!canStop)
                }

                HStack(spacing: 10) {
                    MetricView(title: "Health", value: healthState.rawValue)
                    MetricView(title: "Restarts", value: "\(reconnectCount)")
                    MetricView(title: "Auth", value: "On")
                }

                if let lastMessage {
                    Text(lastMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct AppHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("OlcRTC Gateway")
                    .font(.title3.weight(.bold))
                Text("Local SOCKS bridge for external VPN clients")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

private struct ImportPanel: View {
    @Binding var importText: String
    let importError: String?
    var importFocused: FocusState<Bool>.Binding
    let paste: () -> Void
    let submit: () -> Void

    var body: some View {
        Panel(title: "Импорт", systemImage: "link.badge.plus") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("olcrtc://...", text: $importText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused(importFocused)
                    .lineLimit(3...6)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button(action: paste) {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button(action: submit) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
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
                VStack(spacing: 8) {
                    ForEach(profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isActive: activeProfile?.id == profile.id,
                            isBusy: isBusy,
                            connect: { connect(profile) },
                            remove: { remove(profile) }
                        )
                    }
                }
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
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isActive ? .green : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(profile.carrier) / \(profile.transport)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(profile.clientID)
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
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Type")
                            .foregroundStyle(.secondary)
                        Text("SOCKS5")
                    }
                    GridRow {
                        Text("Host")
                            .foregroundStyle(.secondary)
                        Text("127.0.0.1")
                    }
                    GridRow {
                        Text("Port")
                            .foregroundStyle(.secondary)
                        Text("\(port)")
                    }
                    GridRow {
                        Text("Auth")
                            .foregroundStyle(.secondary)
                        Text("On")
                    }
                    GridRow {
                        Text("User")
                            .foregroundStyle(.secondary)
                        Text(credentials.username)
                    }
                    GridRow {
                        Text("Pass")
                            .foregroundStyle(.secondary)
                        Text(credentials.password)
                    }
                }
                .font(.callout.monospaced())

                HStack(spacing: 10) {
                    Button(action: copySocksLink) {
                        Label(copied == .socks ? "Copied" : "socks://", systemImage: copied == .socks ? "checkmark" : "link")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: copySocks5Link) {
                        Label(copied == .socks5 ? "Copied" : "socks5://", systemImage: copied == .socks5 ? "checkmark" : "link")
                    }
                    .buttonStyle(.bordered)
                }

                Button(action: copySettings) {
                    Label(copied == .settings ? "Скопировано" : "Копировать вручную", systemImage: copied == .settings ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Text("Сначала запускается OlcRTC, потом импортируй socks:// или socks5:// ссылку во внешний VPN-клиент. Если сеть сменилась, выключи туннель во внешнем клиенте, нажми Restart SOCKS и включи его обратно.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DiagnosticsPanel: View {
    let logs: [ProxyLogEntry]
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        Panel(title: "Диагностика", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Последние события")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: copy) {
                        Label(copied ? "Скопировано" : "Копировать лог", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(logs.isEmpty)
                }

                if logs.isEmpty {
                    ContentUnavailableView("Лог пуст", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.level.symbolName)
                .foregroundStyle(entry.level.tint)
                .frame(width: 18)

            Text(entry.line)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
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
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct StatusBadge: View {
    let status: LocalProxyController.Status

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.tint)
                .frame(width: 10, height: 10)
            Text(status.rawValue)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(status.tint.opacity(0.12), in: Capsule())
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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension ProxyLogEntry.Level {
    var tint: Color {
        switch self {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .debug:
            return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        case .debug:
            return "wrench.and.screwdriver.fill"
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
