import AVFoundation
import Foundation
import UIKit

/// Tracks active AVPlayers so Sparks / feed audio cannot keep playing after leaving the screen.
@MainActor
final class MediaPlaybackCoordinator {
    static let shared = MediaPlaybackCoordinator()

    private var players = NSHashTable<AVPlayer>.weakObjects()

    private init() {
        let center = NotificationCenter.default
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.stopAllPlayback()
            }
        }
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.stopAllPlayback()
            }
        }
    }

    func register(_ player: AVPlayer) {
        players.add(player)
    }

    func unregister(_ player: AVPlayer) {
        players.remove(player)
    }

    /// Pause and mute every known player, then release the audio session.
    func stopAllPlayback() {
        stopAllPlayback(except: nil)
    }

    /// Stop every registered player except an optional keep-alive (global hub continuous).
    func stopAllPlayback(except keep: AVPlayer?) {
        for player in players.allObjects {
            if let keep, player === keep { continue }
            player.pause()
            player.isMuted = true
            player.replaceCurrentItem(with: nil)
            players.remove(player)
        }

        if keep == nil {
            players.removeAllObjects()
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// Pause others without tearing them down (e.g. feed → hubs handoff).
    func pauseAll(except keep: AVPlayer? = nil) {
        for player in players.allObjects {
            if let keep, player === keep { continue }
            player.pause()
            player.isMuted = true
        }
    }

    /// Alias used by older call sites.
    func stopAll(reason: String = "") {
        stopAllPlayback()
    }
}
