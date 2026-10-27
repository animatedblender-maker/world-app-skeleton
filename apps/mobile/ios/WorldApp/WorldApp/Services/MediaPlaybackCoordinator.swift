import AVFoundation
import Foundation
import UIKit

extension AVPlayer {
    /// `playImmediately` / `preroll` throw if status isn't ready — that crashed WorldApp on open.
    /// Always honor `rate` — the old `play()` fallback reset Hubs speed to 1x.
    func safePlayImmediately(atRate rate: Float = 1.0) {
        let r = max(0.25, min(rate, 3.0))
        if status == .readyToPlay {
            playImmediately(atRate: r)
        } else {
            play()
            self.rate = r
        }
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
    /// Intentional watch (Masquerade fullscreen/thread, archive) — survives Feed empty-election silence.
    /// Feed stays mounted under Masquerade; `silenceAllOffScreenAudio` used to hard-mute this player.
    private weak var protectedForegroundWatchPlayer: AVPlayer?
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

    /// Pause Sparks/warm-pool audio on resign/minimize; continuous Hubs keeps playing
    /// (UIBackgroundModes audio). Remember non-continuous solo for foreground resume.
    private func noteResignActive() {
        soloPlayingThroughInterrupt = nil
        let continuous = protectedContinuousPlayer
        if let solo = soloPlayer,
           solo !== continuous,
           solo.rate > 0.01
            || solo.timeControlStatus == .playing
            || solo.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            soloPlayingThroughInterrupt = solo
        }
        pauseSparksAudioForAppInactive()
        // Keep continuous hubs butter-smooth through Control Center / app switcher / minimize.
        if let continuous, continuous.currentItem != nil {
            soloPlayer = continuous
            ensurePlaybackAudioSession()
            if continuous.rate < 0.05 {
                continuous.play()
            }
        }
    }

    /// Hard-pause Sparks/feed/warm-pool without tearing items down.
    /// Never touches protected continuous Hubs or intentional Masquerade watch.
    private func pauseSparksAudioForAppInactive() {
        pausedForAppInactive = true
        for player in players.allObjects {
            if isProtected(player) { continue }
            hardSilence(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()
    }

    /// If we paused for resign/background (or the system did), re-solo and let controllers
    /// re-assert mute + play (never play() while still hard-muted from pauseSparksAudio).
    /// Never resume every registered player (that stacked audio from earlier Sparks).
    private func resumeAfterInterrupt() {
        pausedForAppInactive = false
        if let watch = protectedForegroundWatchPlayer, watch.currentItem != nil {
            soloPlayer = watch
            ensurePlaybackAudioSession()
            if watch.rate < 0.05 {
                watch.play()
            }
        } else if let continuous = protectedContinuousPlayer, continuous.currentItem != nil {
            soloPlayer = continuous
            ensurePlaybackAudioSession()
            if continuous.rate < 0.05 {
                continuous.play()
            }
        } else if let player = soloPlayingThroughInterrupt, player.currentItem != nil {
            _ = soloSparkAudio(keeping: player)
            ensurePlaybackAudioSession()
        }
        soloPlayingThroughInterrupt = nil
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
        if protectedForegroundWatchPlayer === player {
            protectedForegroundWatchPlayer = nil
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

    /// Mark an intentional Masquerade/archive watch so Feed silence storms cannot hard-mute it.
    func protectForegroundWatch(_ player: AVPlayer?) {
        protectedForegroundWatchPlayer = player
        if let player {
            soloPlayer = player
            register(player)
        }
    }

    func clearForegroundWatchProtection(for player: AVPlayer? = nil) {
        if let player {
            if protectedForegroundWatchPlayer === player {
                protectedForegroundWatchPlayer = nil
            }
            return
        }
        protectedForegroundWatchPlayer = nil
    }

    /// Continuous hubs player currently protected (mini/watch).
    var continuousHubPlayer: AVPlayer? { protectedContinuousPlayer }

    /// True while Masquerade/archive intentional watch is protected from Feed silence storms.
    var hasForegroundWatchProtection: Bool { protectedForegroundWatchPlayer != nil }

    private func isProtected(_ player: AVPlayer) -> Bool {
        if let keep = protectedContinuousPlayer, player === keep { return true }
        if let keep = protectedForegroundWatchPlayer, player === keep { return true }
        return false
    }

    /// Leave Feed / open Search — kill feed+Sparks audio. Continuous Hubs mini stays.
    /// Lighter than `resetAll` remount storms: no item teardown, next-beat safe.
    func silenceFeedSparksAudioPreservingHubsMini() {
        sparkPageEpoch &+= 1
        soloPlayingThroughInterrupt = nil
        // Stale Masquerade watch must not block Search/tab silence.
        protectedForegroundWatchPlayer = nil
        let keep = protectedContinuousPlayer
        for player in players.allObjects {
            if let keep, player === keep { continue }
            player.pause()
            player.isMuted = true
            player.volume = 0
            player.rate = 0
        }
        SparkWarmPool.shared.hardSilenceAllBuffered()
        if let keep, keep.currentItem != nil {
            soloPlayer = keep
        } else {
            soloPlayer = nil
        }
    }

    /// True when this player is the current Sparks/Hubs audio owner.
    func isSolo(_ player: AVPlayer?) -> Bool {
        guard let player else { return false }
        return soloPlayer === player
    }

    /// **Hard rule:** if video is off-screen / tab changed / Sparks closed — silence everything
    /// except protected continuous Hubs mini/watch and intentional Masquerade/archive watch.
    func silenceAllOffScreenAudio() {
        sparkPageEpoch &+= 1
        let keepContinuous = protectedContinuousPlayer
        let keepWatch = protectedForegroundWatchPlayer
        soloPlayingThroughInterrupt = nil
        // Feather path: continuous hubs already solo + rolling → skip the player walk
        // (still spare an intentional Masquerade watch if one is up).
        if let keepContinuous,
           keepWatch == nil,
           keepContinuous.currentItem != nil,
           keepContinuous.rate >= 0.05,
           soloPlayer === keepContinuous {
            var othersLive = false
            for player in players.allObjects {
                if player === keepContinuous { continue }
                if player.rate > 0.01
                    || player.timeControlStatus == .playing
                    || (!player.isMuted && player.volume > 0.01) {
                    othersLive = true
                    hardSilence(player)
                }
            }
            if othersLive {
                SparkWarmPool.shared.silencePlayingBuffered()
            }
            return
        }
        for player in players.allObjects {
            if isProtected(player) { continue }
            hardSilence(player)
        }
        SparkWarmPool.shared.silenceAllBuffered()
        // Prefer intentional Masquerade watch audio ownership over mini when both exist.
        // Never call play() here — tab-hop silence must stay feather-light (play hitch).
        if let keepWatch, keepWatch.currentItem != nil {
            soloPlayer = keepWatch
        } else if let keepContinuous {
            soloPlayer = keepContinuous
            ensurePlaybackAudioSession()
            if keepContinuous.rate < 0.05, keepContinuous.currentItem != nil {
                keepContinuous.play()
            }
        } else {
            soloPlayer = nil
        }
    }

    /// After tab/nav silence: re-claim continuous hubs audio with the user's mute preference.
    /// Call whenever `hubPlaybackPost != nil` and playback should continue in mini.
    /// No-ops when already solo + playing at the right mute/rate (tab hops must stay light).
    func reassertContinuousHubsAudio(userMuted: Bool, rate: Float = 1.0) {
        guard let keep = protectedContinuousPlayer, keep.currentItem != nil else { return }
        soloPlayer = keep
        register(keep)
        let playRate = max(0.25, min(rate, 3.0))
        let muteOK = keep.isMuted == userMuted && (userMuted || keep.volume > 0.5)
        let rateOK = keep.rate > 0.05 && abs(keep.rate - playRate) <= 0.05
        if muteOK, rateOK, soloPlayer === keep {
            return
        }
        ensurePlaybackAudioSession()
        keep.isMuted = userMuted
        keep.volume = userMuted ? 0 : 1
        if keep.rate < 0.05 || abs(keep.rate - playRate) > 0.05 {
            keep.play()
            keep.safePlayImmediately(atRate: playRate)
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
        let continuous = protectedContinuousPlayer
        let foregroundWatch = protectedForegroundWatchPlayer
        // Intentional Masquerade/archive watch steals from live continuous mini.
        let keepIsForegroundWatch = keep != nil && keep === foregroundWatch
        // Live continuous Hubs wins over feed/Sparks claims. Paused continuous (Sparks overlay)
        // yields so Sparks can solo without tearing the hubs film down.
        // Foreground watch (Masquerade) is allowed to take audio from continuous.
        if let continuous, keep !== continuous, continuous.currentItem != nil, !keepIsForegroundWatch {
            let continuousLive = continuous.rate > 0.01
                || continuous.timeControlStatus == .playing
                || continuous.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if continuousLive {
                if let keep { hardSilence(keep) }
                soloPlayer = continuous
                return false
            }
        }
        if let pageEpoch, pageEpoch != sparkPageEpoch {
            // Don't hard-mute a protected watch on a stale epoch — caller refreshes and retries.
            if let keep, !isProtected(keep) { hardSilence(keep) }
            return false
        }
        soloPlayer = keep
        for player in players.allObjects {
            if let keep, player === keep {
                continue
            }
            if let continuous, player === continuous {
                // Soft-pause mini while Masquerade watch owns audio (keep protection).
                if keepIsForegroundWatch {
                    player.pause()
                    player.isMuted = true
                    player.volume = 0
                }
                continue
            }
            if let foregroundWatch, player === foregroundWatch {
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
        if let continuous = protectedContinuousPlayer,
           player !== continuous,
           player !== protectedForegroundWatchPlayer,
           continuous.currentItem != nil {
            let continuousLive = continuous.rate > 0.01
                || continuous.timeControlStatus == .playing
                || continuous.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if continuousLive {
                hardSilence(player)
                return false
            }
        }
        if let pageEpoch, pageEpoch != sparkPageEpoch {
            if !isProtected(player) {
                hardSilence(player)
            }
            return false
        }
        guard soloPlayer === player else {
            if !isProtected(player) {
                hardSilence(player)
            }
            return false
        }
        return true
    }

    private func hardSilence(_ player: AVPlayer) {
        // Never pause/mute continuous Hubs or intentional Masquerade/archive watch.
        if isProtected(player) {
            return
        }
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
