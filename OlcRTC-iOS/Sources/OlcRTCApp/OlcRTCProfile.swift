import Foundation

struct OlcRTCProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(carrier)|\(transport)|\(roomID)|\(keyHex)|\(clientID)" }
    var secretID: String { "\(carrier)|\(transport)|\(roomID)|\(clientID)" }

    let carrier: String
    let transport: String
    let payload: [String: String]
    let roomID: String
    let keyHex: String
    let clientID: String
    let comment: String

    var hasGeneratedClientID: Bool {
        clientID.hasPrefix("ios-")
    }

    var hasLegacyGeneratedClientID: Bool {
        clientID == DeviceIdentity.legacyProfileClientID(carrier: carrier, roomID: roomID, keyHex: keyHex)
    }

    init(
        carrier: String,
        transport: String,
        payload: [String: String],
        roomID: String,
        keyHex: String,
        clientID: String,
        comment: String
    ) {
        self.carrier = carrier
        self.transport = transport
        self.payload = payload
        self.roomID = roomID
        self.keyHex = keyHex
        self.clientID = clientID
        self.comment = comment
    }

    var displayName: String {
        comment.isEmpty ? "\(carrier) \(transport)" : comment
    }

    var carrierDisplayName: String {
        switch carrier.lowercased() {
        case "jitsi":
            return "Jitsi"
        case "telemost":
            return "Telemost"
        case "wbstream":
            return "WB Stream"
        case "jazz":
            return "Jazz"
        default:
            return carrier
        }
    }

    var transportDisplayName: String {
        switch transport.lowercased() {
        case "datachannel":
            return "Data"
        case "vp8channel":
            return "VP8"
        case "seichannel":
            return "SEI"
        case "videochannel":
            return "Video"
        default:
            return transport
        }
    }

    var compatibilityLabel: String {
        switch (carrier.lowercased(), transport.lowercased()) {
        case ("jitsi", "datachannel"):
            return "stable"
        case ("jitsi", _):
            return "best effort"
        case ("telemost", "vp8channel"):
            return "stable"
        case ("telemost", "videochannel"):
            return "best effort"
        case ("wbstream", "vp8channel"), ("wbstream", "seichannel"), ("wbstream", "videochannel"):
            return "stable"
        default:
            return "custom"
        }
    }

    var isJitsiDatachannel: Bool {
        carrier.lowercased() == "jitsi" && transport.lowercased() == "datachannel"
    }

    var startAttemptCount: Int {
        3
    }

    var startReadyTimeoutMilliseconds: Int {
        if isJitsiDatachannel {
            return 90_000
        }
        switch transport.lowercased() {
        case "vp8channel", "seichannel", "videochannel":
            return 30_000
        default:
            return 12_000
        }
    }

    var tunnelCheckTimeoutNanoseconds: UInt64 {
        if isJitsiDatachannel {
            return 20_000_000_000
        }
        switch transport.lowercased() {
        case "vp8channel", "seichannel", "videochannel":
            return 16_000_000_000
        default:
            return 12_000_000_000
        }
    }

    func runtimeClientID() -> String {
        guard isJitsiDatachannel else {
            return clientID
        }

        let suffix = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .lowercased()
        return "\(clientID)-r\(suffix)"
    }

    var roomLabel: String {
        if carrier.lowercased() == "jitsi",
           let host = URL(string: roomID).flatMap(\.host) {
            return host
        }
        return roomID
    }

    func renamed(_ name: String) -> OlcRTCProfile {
        OlcRTCProfile(
            carrier: carrier,
            transport: transport,
            payload: payload,
            roomID: roomID,
            keyHex: keyHex,
            clientID: clientID,
            comment: name
        )
    }

    func withKeyHex(_ newKeyHex: String) -> OlcRTCProfile {
        OlcRTCProfile(
            carrier: carrier,
            transport: transport,
            payload: payload,
            roomID: roomID,
            keyHex: newKeyHex,
            clientID: clientID,
            comment: comment
        )
    }

    func withClientID(_ newClientID: String) -> OlcRTCProfile {
        OlcRTCProfile(
            carrier: carrier,
            transport: transport,
            payload: payload,
            roomID: roomID,
            keyHex: keyHex,
            clientID: newClientID,
            comment: comment
        )
    }
}

extension OlcRTCProfile {
    init(uri rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("olcrtc://") else {
            throw ParseError.invalidScheme
        }

        let body = String(value.dropFirst("olcrtc://".count))
        let splitKey = body.splitOnce(separator: "#")
        guard let keyAndClient = splitKey.right else {
            throw ParseError.invalidKey
        }

        let normalizedKeyAndClient = keyAndClient.hasPrefix("$")
            ? String(keyAndClient.dropFirst())
            : keyAndClient

        let splitComment = normalizedKeyAndClient.splitOnce(separator: "$")
        let keyAndOptionalClient = splitComment.left
        let comment = splitComment.right ?? ""

        let splitClient = keyAndOptionalClient.splitOnce(separator: "%")
        guard splitClient.left.isHexKey else {
            throw ParseError.invalidKey
        }
        let keyHex = splitClient.left

        let splitRoom = splitKey.left.splitOnce(separator: "@")
        guard let roomID = splitRoom.right, !roomID.isEmpty else {
            throw ParseError.missingRoomID
        }

        let splitTransport = splitRoom.left.splitOnce(separator: "?")
        guard let transportPart = splitTransport.right, !transportPart.isEmpty else {
            throw ParseError.missingTransport
        }

        let carrier = splitTransport.left
        guard !carrier.isEmpty else {
            throw ParseError.missingCarrier
        }

        let clientID = splitClient.right.flatMap { value -> String? in
            let decoded = value.percentDecoded
            return decoded.isEmpty ? nil : decoded
        } ?? DeviceIdentity.profileClientID(
            carrier: carrier.percentDecoded,
            roomID: Self.normalizedRoomID(roomID.percentDecoded, carrier: carrier.percentDecoded),
            keyHex: keyHex
        )

        let parsedTransport = Self.parseTransport(transportPart)
        let decodedCarrier = carrier.percentDecoded
        self.carrier = decodedCarrier
        self.transport = parsedTransport.name
        self.payload = parsedTransport.payload
        self.roomID = Self.normalizedRoomID(roomID.percentDecoded, carrier: decodedCarrier)
        self.keyHex = keyHex
        self.clientID = clientID
        self.comment = comment.percentDecoded
    }

    private static func parseTransport(_ value: String) -> (name: String, payload: [String: String]) {
        guard let start = value.firstIndex(of: "<"),
              let end = value.lastIndex(of: ">"),
              start < end else {
            return (value, [:])
        }

        let name = String(value[..<start])
        let payloadBody = String(value[value.index(after: start)..<end])
        var payload: [String: String] = [:]

        for item in payloadBody.split(separator: "&") {
            let pair = String(item).splitOnce(separator: "=")
            if let right = pair.right {
                payload[pair.left.percentDecoded] = right.percentDecoded
            }
        }

        return (name.percentDecoded, payload)
    }

    private static func normalizedRoomID(_ value: String, carrier: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard carrier.lowercased() == "jitsi",
              !trimmed.lowercased().hasPrefix("http://"),
              !trimmed.lowercased().hasPrefix("https://"),
              trimmed.contains("/"),
              !trimmed.hasPrefix("/") else {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    enum ParseError: LocalizedError {
        case invalidScheme
        case missingCarrier
        case missingTransport
        case missingRoomID
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .invalidScheme:
                return "Link must start with olcrtc://"
            case .missingCarrier:
                return "Carrier is missing"
            case .missingTransport:
                return "Transport is missing"
            case .missingRoomID:
                return "Room ID is missing"
            case .invalidKey:
                return "Encryption key must be 64 hex characters"
            }
        }
    }
}

private extension String {
    var percentDecoded: String {
        removingPercentEncoding ?? self
    }

    var isHexKey: Bool {
        count == 64 && allSatisfy { $0.isHexDigit }
    }

    func splitOnce(separator: Character) -> (left: String, right: String?) {
        guard let index = firstIndex(of: separator) else {
            return (self, nil)
        }

        let left = String(self[..<index])
        let right = String(self[self.index(after: index)...])
        return (left, right)
    }
}
