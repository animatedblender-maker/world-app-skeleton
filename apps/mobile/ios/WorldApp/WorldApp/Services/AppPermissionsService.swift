import AVFAudio
import AVFoundation
import Foundation

@MainActor
final class AppPermissionsService {
    static let shared = AppPermissionsService()

    private init() {}

    /// Requests every essential permission the first time the app is opened.
    /// Prompts are shown one after another so iOS does not stack dialogs.
    func requestEssentialPermissionsOnLaunch() async {
        await requestMicrophoneIfNeeded()
        await pauseBetweenPrompts()
        await requestCameraIfNeeded()
        await pauseBetweenPrompts()
        await PushNotificationService.shared.requestAuthorizationAndRegister()
        await pauseBetweenPrompts()
        _ = await LocationService.shared.requestAuthorizationIfNeeded()
    }

    func requestMicrophoneIfNeeded() async {
        let permission = AVAudioApplication.shared.recordPermission
        guard permission == .undetermined else { return }
        _ = await AVAudioApplication.requestRecordPermission()
    }

    func requestCameraIfNeeded() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        default:
            break
        }
    }

    private func pauseBetweenPrompts() async {
        try? await Task.sleep(nanoseconds: 450_000_000)
    }
}