import AVFoundation
import Foundation
import UIKit

extension AVPlayer {
    /// `playImmediately` / `preroll` throw if status isn't ready — that crashed WorldApp on open.
    func safePlayImmediately(atRate rate: Float = 1.0) {
        guard status == .readyToPlay else {
            play()
            return
        }
        playImmediately(atRate: rate)
    }
}

/// Tracks active AVPlayers so Sparks / feed audio cannot keep playing after leaving the screen.
///
/// **Screenshot / Control Center:** iOS fires `willResignActive` briefly. We must **never**
/// pause or tear down players for that — Hubs, Sparks, and feed video keep playing.
@MainActor
final class MediaPlaybackCoordinator {
    static let shared = MediaPlaybackCoordinator()

    private var players = NSHashTable<AVPlayer>.weakObjects()
    /// Players that were actively playing when the app briefly resigned (screenshot, CC, etc.).
    private var playingThroughInterrupt = NSHashTable<AVPlayer>.weakObjects()

    private init() {
        let center = NotificationCenter.default

        // Screenshots, Control Center, notification shade — do NOT stop playback.
        center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.noteResignActive()
            }
        }

        center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.resumeAfterInterrupt()
            }
        }

        // True background: still do not destroy players. System may throttle audio;
        // we resume on become-active if the user was watching.
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.noteResignActive()
            }
        }
    }

    /// Remember who was playing — never pause here (screenshots use this path).
    private func noteResignActive() {
        for player in players.allObjects {
            if player.rate > 0.01 || player.timeControlStatus == .playing || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                playingThroughInterrupt.add(player)
            }
        }
    }

    /// If the system paused AVPlayers during a brief interrupt, kick them again.
    private func resumeAfterInterrupt() {
        let targets = playingThroughInterrupt.allObjects
        playingThroughInterrupt.removeAllObjects()
        for player in targets {
            guard player.currentItem != nil else { continue }
            // Restore audio session for continuous Hubs / Sparks.
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? session.setActive(true, options: [])
            if player.rate < 0.01 {
                player.play()
                player.safePlayImmediately(atRate: 1.0)
            }
        }
        // Broadcast so Archive / hub controllers re-assert userWantsPlayback.
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    func register(_ player: AVPlayer) {
        players.add(player)
    }

    func unregister(_ player: AVPlayer) {
        players.remove(player)
        playingThroughInterrupt.remove(player)
    }

    /// Pause and mute every known player, then release the audio session.
    /// Only for intentional navigation away — **never** call for screenshots.
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
            playingThroughInterrupt.removeAllObjects()
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
            player.volume = 0
        }
    }

    /// Sparks page change: hard-silence every registered player (including warm-pool buffers).
    /// The newly active card re-enables audio on itself after this runs.
    func silenceForSparkPageChange() {
        for player in players.allObjects {
            player.pause()
            player.isMuted = true
            player.volume = 0
        }
    }

    /// Only `keep` may produce sound — used when a Spark becomes the focused page.
    func soloSparkAudio(keeping keep: AVPlayer?) {
        for player in players.allObjects {
            if let keep, player === keep {
                continue
            }
            player.pause()
            player.isMuted = true
            player.volume = 0
        }
    }

    /// Alias used by older call sites.
    func stopAll(reason: String = "") {
        stopAllPlayback()
    }
}

extension Notification.Name {
    /// Posted after screenshot / Control Center / brief resign — controllers should keep playing.
    static let matteryaResumePlaybackAfterInterrupt = Notification.Name("matterya.resumePlaybackAfterInterrupt")
}
