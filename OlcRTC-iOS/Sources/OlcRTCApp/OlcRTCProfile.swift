import Foundation

struct OlcRTCProfile: Identifiable, Codable, Equatable, Sendable {
    var id: String { "\(carrier)|\(transport)|\(roomID)|\(clientID)" }

    let carrier: String
    let transport: String
    let payload: [String: String]
    let roomID: String
    let keyHex: String
    let clientID: String
    let comment: String

    var displayName: String {
        comment.isEmpty ? "\(carrier) \(transport)" : comment
    }
}

extension OlcRTCProfile {
    init(uri rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("olcrtc://") else {
            throw ParseError.invalidScheme
        }

        let body = String(value.dropFirst("olcrtc://".count))
        let splitComment = body.splitOnce(separator: "$")
        let leftOfComment = splitComment.left
        let comment = splitComment.right ?? ""

        let splitKey = leftOfComment.splitOnce(separator: "#")
        guard let keyAndClient = splitKey.right else {
            throw ParseError.invalidKey
        }

        let splitClient = keyAndClient.splitOnce(separator: "%")
        guard splitClient.left.isHexKey else {
            throw ParseError.invalidKey
        }
        let keyHex = splitClient.left

        guard let clientID = splitClient.right, !clientID.isEmpty else {
            throw ParseError.missingClientID
        }

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

        let parsedTransport = Self.parseTransport(transportPart)
        self.carrier = carrier.percentDecoded
        self.transport = parsedTransport.name
        self.payload = parsedTransport.payload
        self.roomID = roomID.percentDecoded
        self.keyHex = keyHex
        self.clientID = clientID.percentDecoded
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

    enum ParseError: LocalizedError {
        case invalidScheme
        case missingCarrier
        case missingTransport
        case missingRoomID
        case invalidKey
        case missingClientID

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
            case .missingClientID:
                return "Client ID is missing"
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
