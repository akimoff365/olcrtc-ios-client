import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var store: ProfileStore
    @EnvironmentObject private var proxy: LocalProxyController
    @State private var importText = ""
    @State private var importError: String?
    @State private var copiedProxy = false
    @FocusState private var importFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ConnectionPanel(
                        status: proxy.status,
                        networkName: proxy.networkName,
                        activeProfile: proxy.activeProfile,
                        reconnectCount: proxy.reconnectCount,
                        lastMessage: proxy.lastMessage,
                        reconnect: proxy.reconnect,
                        stop: proxy.stop,
                        canReconnect: proxy.canReconnect,
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
                        isBusy: proxy.status == .starting || proxy.status == .reconnecting,
                        connect: { profile in
                            Task {
                                await proxy.start(profile: profile)
                            }
                        },
                        remove: store.remove
                    )

                    ProxyPanel(
                        port: proxy.socksPort,
                        copied: copiedProxy,
                        copy: copyProxySettings
                    )
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("OlcRTC")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        proxy.reconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!proxy.canReconnect)

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
        Auth: Off
        """
        copiedProxy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedProxy = false
        }
        #endif
    }
}

private struct ConnectionPanel: View {
    let status: LocalProxyController.Status
    let networkName: String
    let activeProfile: OlcRTCProfile?
    let reconnectCount: Int
    let lastMessage: String?
    let reconnect: () -> Void
    let stop: () -> Void
    let canReconnect: Bool
    let canStop: Bool

    var body: some View {
        Panel(title: "Подключение", systemImage: status.symbolName) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    StatusBadge(status: status)
                    Spacer()
                    NetworkBadge(name: networkName)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(activeProfile?.displayName ?? "Профиль не выбран")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(activeProfile.map { "\($0.carrier) / \($0.transport)" } ?? "SOCKS выключен")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(action: reconnect) {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canReconnect)

                    Button(role: .destructive, action: stop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canStop)
                }

                HStack(spacing: 16) {
                    MetricView(title: "Reconnects", value: "\(reconnectCount)")
                    MetricView(title: "Mode", value: "SOCKS5")
                }

                if let lastMessage {
                    Text(lastMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
    let copied: Bool
    let copy: () -> Void

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
                        Text("Off")
                    }
                }
                .font(.callout.monospaced())

                Button(action: copy) {
                    Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension LocalProxyController.Status {
    var tint: Color {
        switch self {
        case .running:
            return .green
        case .starting, .reconnecting:
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
        case .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .stopped:
            return "power"
        }
    }
}
