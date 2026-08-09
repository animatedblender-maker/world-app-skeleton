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
/// **Solo audio:** only one player may produce sound at a time. Warm-pool buffers and
/// inactive pager cards stay registered but hard-muted — prevents “voice from two Sparks ago”.
///
/// **Screenshot / Control Center:** iOS fires `willResignActive` briefly. We must **never**
/// pause or tear down players for that — Hubs, Sparks, and feed video keep playing.
@MainActor
final class MediaPlaybackCoordinator {
    static let shared = MediaPlaybackCoordinator()

    private var players = NSHashTable<AVPlayer>.weakObjects()
    /// The only player allowed to have volume > 0 / rate > 0 with audio.
    private weak var soloPlayer: AVPlayer?
    /// Solo player that was actively playing when the app briefly resigned (screenshot, CC, etc.).
    private weak var soloPlayingThroughInterrupt: AVPlayer?
    /// Bumps on every Sparks page change so late observers from the previous page cannot re-solo.
    private(set) var sparkPageEpoch: UInt64 = 0

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

    /// Remember who was solo-playing — never pause here (screenshots use this path).
    private func noteResignActive() {
        soloPlayingThroughInterrupt = nil
        guard let solo = soloPlayer else { return }
        if solo.rate > 0.01
            || solo.timeControlStatus == .playing
            || solo.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            soloPlayingThroughInterrupt = solo
        }
    }

    /// If the system paused the solo AVPlayer during a brief interrupt, kick only that one.
    /// Never resume every registered player (that stacked audio from earlier Sparks).
    private func resumeAfterInterrupt() {
        let target = soloPlayingThroughInterrupt
        soloPlayingThroughInterrupt = nil
        guard let player = target, player.currentItem != nil else {
            NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
            return
        }
        // Solo again in case a warm-pool buffer leaked rate while we were away.
        soloSparkAudio(keeping: player)
        let session = AVAudioSession.sharedInstance()
        // Never mixWithOthers — other app audio can sit under Sparks; other players must stay muted.
        try? session.setCategory(.playback, mode: .moviePlayback, options: [])
        try? session.setActive(true, options: [])
        if player.rate < 0.01 {
            player.play()
            player.safePlayImmediately(atRate: 1.0)
        }
        // Broadcast so Archive / hub controllers re-assert userWantsPlayback on the solo only.
        NotificationCenter.default.post(name: .matteryaResumePlaybackAfterInterrupt, object: nil)
    }

    func register(_ player: AVPlayer) {
        players.add(player)
    }

    func unregister(_ player: AVPlayer) {
        players.remove(player)
        if soloPlayer === player {
            soloPlayer = nil
        }
        if soloPlayingThroughInterrupt === player {
            soloPlayingThroughInterrupt = nil
        }
    }

    /// True when this player is the current Sparks/Hubs audio owner.
    func isSolo(_ player: AVPlayer?) -> Bool {
        guard let player else { return false }
        return soloPlayer === player
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
            hardSilence(player)
            player.replaceCurrentItem(with: nil)
            players.remove(player)
        }

        if let keep {
            soloPlayer = keep
        } else {
            soloPlayer = nil
            players.removeAllObjects()
            soloPlayingThroughInterrupt = nil
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// Pause others without tearing them down (e.g. feed → hubs handoff).
    func pauseAll(except keep: AVPlayer? = nil) {
        for player in players.allObjects {
            if let keep, player === keep { continue }
            hardSilence(player)
        }
        if let keep {
            soloPlayer = keep
        } else {
            soloPlayer = nil
        }
    }

    /// Sparks page change: kill the *outgoing* page’s audio only.
    ///
    /// Critical: do **not** hard-silence every registered player. Neighbor / warm-pool
    /// items are already paused at t≈0 with a decoded first frame — blasting pause/mute
    /// across them forces the incoming card to re-cover with poster/black before play.
    func silenceForSparkPageChange() {
        sparkPageEpoch &+= 1
        let previous = soloPlayer
        soloPlayer = nil
        soloPlayingThroughInterrupt = nil
        if let previous {
            hardSilence(previous)
        }
        // Catch any non-solo player that still has rate (ghost audio) without touching
        // parked warm buffers that are already silent at t≈0.
        for player in players.allObjects {
            if let previous, player === previous { continue }
            if player.rate > 0.01
                || player.timeControlStatus == .playing
                || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                hardSilence(player)
            }
        }
        SparkWarmPool.shared.silenceAllBuffered()
    }

    /// Only `keep` may produce sound — used when a Spark becomes the focused page.
    /// - Parameter pageEpoch: when non-nil, reject if a newer page-change already happened.
    /// - Parameter aggressive: when true (comments / share overlay), hard-silence **every**
    ///   other player even if already paused — kills ghost audio from off-screen cells that
    ///   still think they are active.
    @discardableResult
    func soloSparkAudio(
        keeping keep: AVPlayer?,
        pageEpoch: UInt64? = nil,
        aggressive: Bool = false
    ) -> Bool {
        if let pageEpoch, pageEpoch != sparkPageEpoch {
            if let keep { hardSilence(keep) }
            return false
        }
        soloPlayer = keep
        for player in players.allObjects {
            if let keep, player === keep {
                continue
            }
            if aggressive {
                hardSilence(player)
                continue
            }
            // Soft path: only silence players that are actually producing sound / rate.
            // Hard-pausing warm parked items was nuking their first-frame cache path.
            if player.rate > 0.01
                || player.timeControlStatus == .playing
                || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                || (!player.isMuted && player.volume > 0.01) {
                hardSilence(player)
            }
        }
        return true
    }

    /// Comments / share sheet opened under Sparks: only the current solo may keep audio.
    /// Call after overlays that broadcast resume — prevents “older Spark voice” ghosts.
    func enforceSoloAudioOnly() {
        let keep = soloPlayer
        for player in players.allObjects {
            if let keep, player === keep { continue }
            hardSilence(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()
        // Re-assert solo is unmuted if it was playing (overlay may have stolen focus).
        if let keep, keep.currentItem != nil {
            // Do not force play here — caller decides. Just ensure others are dead.
            soloPlayer = keep
        }
    }

    /// Current solo player (for overlays that must re-kick only the focused Spark).
    var currentSoloPlayer: AVPlayer? { soloPlayer }

    /// Call before any `play()` from a Spark/feed observer. Non-solo players stay silent.
    @discardableResult
    func allowPlaybackIfSolo(_ player: AVPlayer, pageEpoch: UInt64? = nil) -> Bool {
        if let pageEpoch, pageEpoch != sparkPageEpoch {
            hardSilence(player)
            return false
        }
        guard soloPlayer === player else {
            hardSilence(player)
            return false
        }
        return true
    }

    private func hardSilence(_ player: AVPlayer) {
        player.pause()
        player.isMuted = true
        player.volume = 0
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
