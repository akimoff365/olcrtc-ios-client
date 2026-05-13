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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("olcrtc://...", text: $importText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3...6)

                    Button("Import Profile") {
                        importProfile()
                    }
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let importError {
                        Text(importError)
                            .foregroundStyle(.red)
                    }
                }

                Section("Profiles") {
                    if store.profiles.isEmpty {
                        ContentUnavailableView("No profiles", systemImage: "link.badge.plus")
                    } else {
                        ForEach(store.profiles) { profile in
                            ProfileRow(profile: profile) {
                                Task {
                                    await proxy.start(profile: profile)
                                }
                            }
                        }
                        .onDelete(perform: store.remove)
                    }
                }

                Section("Status") {
                    LabeledContent("SOCKS", value: proxy.status.rawValue)
                    LabeledContent("Address", value: "127.0.0.1:\(proxy.socksPort)")
                    LabeledContent("Auth", value: "None")
                    LabeledContent("Reconnects", value: "\(proxy.reconnectCount)")
                    if let message = proxy.lastMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Proxy") {
                    ProxyDetailsView(
                        port: proxy.socksPort,
                        copied: copiedProxy,
                        copy: copyProxySettings
                    )
                }
            }
            .navigationTitle("OlcRTC")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Reconnect") {
                        proxy.reconnect()
                    }
                    .disabled(proxy.activeProfile == nil || proxy.status == .stopped || proxy.status == .starting || proxy.status == .reconnecting)

                    Button("Stop") {
                        proxy.stop()
                    }
                    .disabled(proxy.status == .stopped)
                }
            }
        }
    }

    private func importProfile() {
        do {
            let profile = try OlcRTCProfile(uri: importText)
            store.upsert(profile)
            importText = ""
            importError = nil
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
        Username: 
        Password: 
        """
        copiedProxy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedProxy = false
        }
        #endif
    }
}

private struct ProfileRow: View {
    let profile: OlcRTCProfile
    let connect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.headline)
                    Text("\(profile.carrier) / \(profile.transport)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect", action: connect)
            }

            Text("Client: \(profile.clientID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct ProxyDetailsView: View {
    let port: Int
    let copied: Bool
    let copy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
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

            Button(copied ? "Copied" : "Copy Proxy Settings", action: copy)

            Text("OlcRTC waits for iOS to finish switching between Wi-Fi and LTE, then reconnects automatically. If Happ keeps an old failed connection, tap Reconnect here and reconnect in Happ.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
