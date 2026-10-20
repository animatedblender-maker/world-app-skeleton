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
/// **Resign / minimize:** pause Sparks + warm-pool audio so old clips never keep playing
/// when the app is backgrounded. Brief resign (screenshot / Control Center) resumes the
/// prior solo on `didBecomeActive` — items stay intact (no teardown).
@MainActor
final class MediaPlaybackCoordinator {
    static let shared = MediaPlaybackCoordinator()

    private var players = NSHashTable<AVPlayer>.weakObjects()
    /// The only player allowed to have volume > 0 / rate > 0 with audio.
    private weak var soloPlayer: AVPlayer?
    /// Continuous Hubs AVPlayer — never kill when silencing feed/Sparks (tab switch / focus loss).
    private weak var protectedContinuousPlayer: AVPlayer?
    /// Solo player that was actively playing when the app briefly resigned (screenshot, CC, etc.).
    private weak var soloPlayingThroughInterrupt: AVPlayer?
    /// True while we paused for resign/background — resume only the remembered solo.
    private var pausedForAppInactive = false
    /// Bumps on every Sparks page change so late observers from the previous page cannot re-solo.
    private(set) var sparkPageEpoch: UInt64 = 0
    /// Debounce AVAudioSession activation — main-thread setActive freezes UI (SessionCore).
    private var audioSessionArmed = false
    private var audioArmTask: Task<Void, Never>?
    /// Serial background queue for setActive / setCategory (never the main thread).
    private static let audioSessionQueue = DispatchQueue(
        label: "com.matterya.audioSession",
        qos: .userInitiated
    )

    private init() {
        let center = NotificationCenter.default

        // Resign / Control Center / notification shade — pause Sparks audio (resume on active).
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

        // True background: pause (do not destroy). Resume on become-active if still watching.
        center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.noteResignActive()
            }
        }

        // Keyboard / system may deactivate the session without killing players —
        // clear the armed flag so the next ensurePlaybackAudioSession re-arms off main.
        center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let typeValue,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue),
                  type == .began else { return }
            Task { @MainActor in
                MediaPlaybackCoordinator.shared.markAudioSessionInactive()
            }
        }
    }

    /// Pause Sparks/warm-pool audio on resign/minimize; remember solo for foreground resume.
    private func noteResignActive() {
        soloPlayingThroughInterrupt = nil
        if let solo = soloPlayer,
           solo.rate > 0.01
            || solo.timeControlStatus == .playing
            || solo.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            soloPlayingThroughInterrupt = solo
        }
        pauseSparksAudioForAppInactive()
    }

    /// Hard-pause every registered + warm-pool player without tearing items down.
    /// Keeps `soloPlayer` identity so resume can re-kick only that one.
    private func pauseSparksAudioForAppInactive() {
        pausedForAppInactive = true
        for player in players.allObjects {
            hardSilence(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()
    }

    /// If we paused for resign/background (or the system did), re-solo and let controllers
    /// re-assert mute + play (never play() while still hard-muted from pauseSparksAudio).
    /// Never resume every registered player (that stacked audio from earlier Sparks).
    private func resumeAfterInterrupt() {
        pausedForAppInactive = false
        let target = soloPlayingThroughInterrupt
        soloPlayingThroughInterrupt = nil
        if let player = target, player.currentItem != nil {
            // Re-claim solo; controllers unmute + play via the broadcast below.
            _ = soloSparkAudio(keeping: player)
            ensurePlaybackAudioSession()
        }
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
        if protectedContinuousPlayer === player {
            protectedContinuousPlayer = nil
        }
    }

    /// Mark the global continuous Hubs player so tab switches never kill mini audio.
    func protectContinuous(_ player: AVPlayer?) {
        protectedContinuousPlayer = player
        if let player {
            soloPlayer = player
            register(player)
        }
    }

    func clearContinuousProtection() {
        protectedContinuousPlayer = nil
    }

    /// Continuous hubs player currently protected (mini/watch).
    var continuousHubPlayer: AVPlayer? { protectedContinuousPlayer }

    /// True when this player is the current Sparks/Hubs audio owner.
    func isSolo(_ player: AVPlayer?) -> Bool {
        guard let player else { return false }
        return soloPlayer === player
    }

    /// **Hard rule:** if video is off-screen / tab changed / Sparks closed — silence everything
    /// except the optional protected continuous Hubs mini/watch player.
    func silenceAllOffScreenAudio() {
        sparkPageEpoch &+= 1
        let keep = protectedContinuousPlayer
        soloPlayingThroughInterrupt = nil
        for player in players.allObjects {
            if let keep, player === keep { continue }
            hardSilence(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()
        if let keep {
            soloPlayer = keep
            // Tab silence must never leave continuous hubs muted/stalled.
            // (Other paths may have hard-silenced before protect was re-bound.)
        } else {
            soloPlayer = nil
        }
    }

    /// After tab/nav silence: re-claim continuous hubs audio with the user's mute preference.
    /// Call whenever `hubPlaybackPost != nil` and playback should continue in mini.
    func reassertContinuousHubsAudio(userMuted: Bool) {
        guard let keep = protectedContinuousPlayer, keep.currentItem != nil else { return }
        soloPlayer = keep
        register(keep)
        ensurePlaybackAudioSession()
        keep.isMuted = userMuted
        keep.volume = userMuted ? 0 : 1
        if keep.rate < 0.05 {
            keep.play()
            keep.safePlayImmediately(atRate: 1.0)
        }
    }

    /// Activate playback audio session **off the main thread** (Apple: setActive on main freezes UI).
    /// Safe to call often — debounced / one-shot until stopAll or interruption.
    func ensurePlaybackAudioSession() {
        if audioSessionArmed { return }
        audioArmTask?.cancel()
        // Optimistic arm so rapid applyUserAudioOutput calls don't enqueue N setActives.
        audioSessionArmed = true
        audioArmTask = Task(priority: .userInitiated) {
            await Self.activatePlaybackSessionOffMain()
        }
    }

    /// Blocking setActive on a background queue — never call from MainActor work.
    private static func activatePlaybackSessionOffMain() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            audioSessionQueue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback, options: [])
                try? session.setActive(true, options: [])
                cont.resume()
            }
        }
    }

    private static func deactivatePlaybackSessionOffMain() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            audioSessionQueue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setActive(false, options: [.notifyOthersOnDeactivation])
                cont.resume()
            }
        }
    }

    fileprivate func markAudioSessionInactive() {
        audioSessionArmed = false
        audioArmTask?.cancel()
        audioArmTask = nil
    }

    /// Pause and mute every known player, then release the audio session.
    /// Only for intentional navigation away — **never** call for screenshots.
    func stopAllPlayback() {
        stopAllPlayback(except: nil)
    }

    /// Stop every registered player except an optional keep-alive (global hub continuous).
    func stopAllPlayback(except keep: AVPlayer?) {
        // When keep is nil → full stop (including continuous). When keep set → spare that one.
        // silenceAllOffScreenAudio uses pauseAll which spares protected continuous.
        let spare = keep
        for player in players.allObjects {
            if let spare, player === spare { continue }
            hardSilence(player)
            player.replaceCurrentItem(with: nil)
            players.remove(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()

        if let spare {
            soloPlayer = spare
        } else {
            soloPlayer = nil
            protectedContinuousPlayer = nil
            players.removeAllObjects()
            soloPlayingThroughInterrupt = nil
            markAudioSessionInactive()
            Task(priority: .utility) {
                await Self.deactivatePlaybackSessionOffMain()
            }
        }
    }

    /// Pause others without tearing them down (e.g. feed → hubs handoff).
    func pauseAll(except keep: AVPlayer? = nil) {
        let protected = keep ?? protectedContinuousPlayer
        for player in players.allObjects {
            if let protected, player === protected { continue }
            hardSilence(player)
        }
        if let protected {
            soloPlayer = protected
        } else {
            soloPlayer = nil
        }
        SparkWarmPool.shared.silenceAllBuffered()
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
        // Catch ghost audio (rate or unmuted volume) without nuking silent t≈0 warm buffers.
        for player in players.allObjects {
            if let previous, player === previous { continue }
            if player.rate > 0.01
                || player.timeControlStatus == .playing
                || player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                || (!player.isMuted && player.volume > 0.01) {
                hardSilence(player)
            }
        }
        // Warm slots that somehow kept rate (continuing park leak) — pause only those.
        SparkWarmPool.shared.silencePlayingBuffered()
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
    /// Mini chrome → continuous Hubs AVPlayer without re-hosting the SwiftUI tree.
    /// userInfo: `playing` (Bool).
    static let matteryaHubContinuousSetPlaying = Notification.Name("matterya.hub.continuous.setPlaying")
    /// Mini chrome mute without re-host. userInfo: `muted` (Bool).
    static let matteryaHubContinuousSetMuted = Notification.Name("matterya.hub.continuous.setMuted")
}
