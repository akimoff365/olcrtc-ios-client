import Foundation

enum RoutingPreset: String, CaseIterable, Identifiable {
    case allProxy
    case simpleRU
    case blockedOnly
    case localOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allProxy:
            return "Весь трафик"
        case .simpleRU:
            return "Simple-RU"
        case .blockedOnly:
            return "Только блокировки"
        case .localOnly:
            return "Локальные мимо"
        }
    }

    var subtitle: String {
        switch self {
        case .allProxy:
            return "Все соединения идут через olcRTC"
        case .simpleRU:
            return "RU/private/Apple напрямую, заблокированное через olcRTC"
        case .blockedOnly:
            return "Через olcRTC только выбранные geosite-правила"
        case .localOnly:
            return "Только private/local CIDR идут напрямую"
        }
    }

    var directRuleSets: [String] {
        switch self {
        case .allProxy:
            return ["geosite-private"]
        case .simpleRU:
            return ["geosite-private", "geosite-ru", "geoip-ru", "geosite-apple"]
        case .blockedOnly:
            return ["geosite-private", "geosite-ru", "geoip-ru"]
        case .localOnly:
            return ["geosite-private"]
        }
    }

    var proxyRuleSets: [String] {
        switch self {
        case .allProxy, .localOnly:
            return []
        case .simpleRU:
            return ["geosite-youtube", "geosite-category-ban-ru"]
        case .blockedOnly:
            return ["geosite-youtube", "geosite-category-ban-ru"]
        }
    }

    var finalOutbound: String {
        switch self {
        case .blockedOnly:
            return "direct"
        case .allProxy, .simpleRU, .localOnly:
            return "olcrtc"
        }
    }

    var usesRuleSets: Bool {
        !directRuleSets.isEmpty || !proxyRuleSets.isEmpty
    }
}

struct SingBoxRoutingConfigBuilder {
    let socksPort: Int
    let credentials: SocksCredentials
    let preset: RoutingPreset
    let includeTunInbound: Bool

    init(
        socksPort: Int,
        credentials: SocksCredentials,
        preset: RoutingPreset,
        includeTunInbound: Bool = true
    ) {
        self.socksPort = socksPort
        self.credentials = credentials
        self.preset = preset
        self.includeTunInbound = includeTunInbound
    }

    func makeConfig() throws -> String {
        var config: [String: Any] = [
            "log": [
                "level": "warn"
            ],
            "dns": [
                "servers": [
                    [
                        "tag": "remote",
                        "address": "https://1.1.1.1/dns-query",
                        "detour": "olcrtc"
                    ],
                    [
                        "tag": "local",
                        "address": "https://1.0.0.1/dns-query",
                        "detour": "direct"
                    ]
                ],
                "strategy": "ipv4_only"
            ],
            "outbounds": [
                [
                    "type": "socks",
                    "tag": "olcrtc",
                    "server": "127.0.0.1",
                    "server_port": socksPort,
                    "version": "5",
                    "username": credentials.username,
                    "password": credentials.password
                ],
                [
                    "type": "direct",
                    "tag": "direct"
                ],
                [
                    "type": "block",
                    "tag": "block"
                ]
            ],
            "route": [
                "rule_set": ruleSets(),
                "rules": routeRules(),
                "final": preset.finalOutbound,
                "auto_detect_interface": true
            ]
        ]

        if includeTunInbound {
            config["inbounds"] = [
                [
                    "type": "tun",
                    "tag": "tun-in",
                    "address": ["172.19.0.1/30"],
                    "mtu": 1280,
                    "auto_route": true,
                    "strict_route": false,
                    "stack": "system"
                ]
            ]
        } else {
            config["inbounds"] = [
                [
                    "type": "mixed",
                    "tag": "validation-in",
                    "listen": "127.0.0.1",
                    "listen_port": 0
                ]
            ]
        }

        let data = try JSONSerialization.data(
            withJSONObject: config,
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(decoding: data, as: UTF8.self)
    }

    private func routeRules() -> [[String: Any]] {
        var rules: [[String: Any]] = [
            [
                "ip_is_private": true,
                "outbound": "direct"
            ]
        ]

        if !preset.directRuleSets.isEmpty {
            rules.append([
                "rule_set": preset.directRuleSets,
                "outbound": "direct"
            ])
        }

        if !preset.proxyRuleSets.isEmpty {
            rules.append([
                "rule_set": preset.proxyRuleSets,
                "outbound": "olcrtc"
            ])
        }

        return rules
    }

    private func ruleSets() -> [[String: Any]] {
        let allRuleSets = Set(preset.directRuleSets + preset.proxyRuleSets)
        return allRuleSets
            .sorted()
            .map { tag in
                [
                    "type": "remote",
                    "tag": tag,
                    "format": "binary",
                    "url": ruleSetURL(tag: tag),
                    "download_detour": "olcrtc"
                ]
            }
    }

    private func ruleSetURL(tag: String) -> String {
        switch tag {
        case "geoip-ru":
            return "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
        case "geosite-private":
            return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-private.srs"
        case "geosite-ru":
            return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs"
        case "geosite-apple":
            return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-apple.srs"
        case "geosite-youtube":
            return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-youtube.srs"
        case "geosite-category-ban-ru":
            return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs"
        default:
            return ""
        }
    }
}
