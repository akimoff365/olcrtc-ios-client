import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class BackgroundKeepAlive {
    static let shared = BackgroundKeepAlive()

    private var player: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var didConfigureRemoteCommands = false

    private init() {}

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try session.setActive(true)

        if player == nil {
            player = try AVAudioPlayer(data: Self.keepAliveWAVData())
            player?.numberOfLoops = -1
            player?.volume = 0.02
            player?.prepareToPlay()
        }

        configureRemoteCommandsIfNeeded()
        updateNowPlayingInfo(isPlaying: true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        beginBackgroundTask()
        player?.play()
    }

    func stop() {
        player?.stop()
        updateNowPlayingInfo(isPlaying: false)
        UIApplication.shared.endReceivingRemoteControlEvents()
        endBackgroundTask()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func refresh() {
        guard let player else {
            return
        }

        if !player.isPlaying {
            player.play()
        }
        updateNowPlayingInfo(isPlaying: true)
        beginBackgroundTask()
    }

    private func configureRemoteCommandsIfNeeded() {
        guard !didConfigureRemoteCommands else {
            return
        }

        didConfigureRemoteCommands = true
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = false
        commandCenter.stopCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
            return .success
        }

        commandCenter.stopCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
            return .success
        }
    }

    private func updateNowPlayingInfo(isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "OlcRTC Link",
            MPMediaItemPropertyArtist: "Secure relay session",
            MPMediaItemPropertyAlbumTitle: "OlcRTC",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
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
