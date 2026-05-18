import AVFoundation
import Foundation
import UIKit

@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private var player: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)

        if player == nil {
            player = try AVAudioPlayer(data: Self.keepAliveWAVData())
            player?.numberOfLoops = -1
            player?.volume = 0.01
            player?.prepareToPlay()
        }

        beginBackgroundTask()
        player?.play()
    }

    func stop() {
        player?.stop()
        endBackgroundTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func beginBackgroundTask() {
        guard backgroundTaskID == .invalid else {
            return
        }

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OlcRTCKeepAlive") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else {
            return
        }

        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private static func keepAliveWAVData() -> Data {
        let sampleRate: UInt32 = 8_000
        let durationSeconds: UInt32 = 30
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = sampleRate * durationSeconds * UInt32(blockAlign)
        let sampleCount = Int(sampleRate * durationSeconds)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(channels.littleEndianData)
        data.append(sampleRate.littleEndianData)
        data.append(byteRate.littleEndianData)
        data.append(blockAlign.littleEndianData)
        data.append(bitsPerSample.littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndianData)
        for index in 0..<sampleCount {
            let value: Int16 = index.isMultiple(of: 2) ? 1 : -1
            data.append(value.littleEndianData)
        }
        return data
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
