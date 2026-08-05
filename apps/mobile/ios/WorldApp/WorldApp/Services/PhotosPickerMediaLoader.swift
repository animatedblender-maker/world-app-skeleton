import CoreTransferable
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Loads image bytes from `PhotosPickerItem` in a way that works on:
/// - real iPhones
/// - **My Mac (Designed for iPad)** where `loadTransferable(Data.self)` often fails for
///   iCloud-only library assets (`CloudPhotoLibraryErrorDomain` 1005 / helper app 4101).
enum PhotosPickerMediaLoader {
    enum LoadError: LocalizedError {
        case empty
        case notAnImage
        case iCloudNotDownloaded
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Couldn't read that photo."
            case .notAnImage:
                return "That file isn't a supported image."
            case .iCloudNotDownloaded:
                return "This photo is only in iCloud and isn't on this Mac yet. Open the Photos app, download it (cloud icon), then try again — or use “Choose from Files” and pick a local image."
            case .underlying(let error):
                return Self.friendlyMessage(for: error)
            }
        }

        static func friendlyMessage(for error: Error) -> String {
            var domains: [String] = []
            var codes: [Int] = []
            var current: Error? = error
            while let err = current {
                let nsErr = err as NSError
                domains.append(nsErr.domain)
                codes.append(nsErr.code)
                current = nsErr.userInfo[NSUnderlyingErrorKey] as? Error
            }

            if domains.contains("CloudPhotoLibraryErrorDomain")
                || domains.contains("PHAssetExportRequestErrorDomain")
                || (domains.contains(NSCocoaErrorDomain) && codes.contains(4101))
            {
                return LoadError.iCloudNotDownloaded.errorDescription
                    ?? "This photo is only in iCloud and isn't available offline."
            }
            if domains.contains(NSItemProvider.errorDomain) {
                return LoadError.iCloudNotDownloaded.errorDescription
                    ?? "This photo is only in iCloud and isn't available offline."
            }
            return error.localizedDescription
        }
    }

    /// JPEG data ready for upload / preview (max long edge ~2400).
    static func loadJPEGData(from item: PhotosPickerItem, compressionQuality: CGFloat = 0.88) async throws -> Data {
        let raw = try await loadRawImageData(from: item)
        return try normalizeToJPEG(raw, quality: compressionQuality)
    }

    /// Best-effort multi-path load. Prefer PhotoKit (can pull from iCloud) over Transferable.
    static func loadRawImageData(from item: PhotosPickerItem) async throws -> Data {
        var lastError: Error?

        // 1) PhotoKit by asset id — allows network download of iCloud originals.
        if let id = item.itemIdentifier, !id.isEmpty {
            do {
                if let data = try await loadViaPhotoKit(localIdentifier: id) {
                    return data
                }
            } catch {
                lastError = error
            }
        }

        // 2) File / image Transferable (JPEG, HEIC, PNG, generic image).
        do {
            if let picked = try await item.loadTransferable(type: PickedImageData.self) {
                return picked.data
            }
        } catch {
            lastError = error
        }

        // 3) Legacy Data transferable (often requests public.png and fails on Mac).
        do {
            if let data = try await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                return data
            }
        } catch {
            lastError = error
        }

        if let lastError {
            throw LoadError.underlying(lastError)
        }
        throw LoadError.empty
    }

    /// Load JPEG from a file URL (Files / drag-drop fallback on Mac).
    static func loadJPEGData(fromFileURL url: URL, compressionQuality: CGFloat = 0.88) async throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let raw = try Data(contentsOf: url)
        return try normalizeToJPEG(raw, quality: compressionQuality)
    }

    // MARK: - PhotoKit

    private static func loadViaPhotoKit(localIdentifier: String) async throws -> Data? {
        let status = await requestPhotoLibraryAccessIfNeeded()
        guard status == .authorized || status == .limited else {
            return nil
        }

        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        // Prefer resource manager (full file, network allowed).
        if let data = try await loadViaAssetResource(asset) {
            return data
        }

        // Fallback: image data request with network.
        return try await loadViaImageManager(asset)
    }

    private static func requestPhotoLibraryAccessIfNeeded() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            return await withCheckedContinuation { cont in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    cont.resume(returning: status)
                }
            }
        }
        return current
    }

    private static func loadViaAssetResource(_ asset: PHAsset) async throws -> Data? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferred = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first(where: { $0.type == .fullSizeVideo }) // unlikely for images
            ?? resources.first
        guard let resource = preferred else { return nil }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withCheckedThrowingContinuation { cont in
            var buffer = Data()
            var finished = false
            PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
                buffer.append(chunk)
            } completionHandler: { error in
                guard !finished else { return }
                finished = true
                if let error {
                    cont.resume(throwing: error)
                } else if buffer.isEmpty {
                    cont.resume(returning: nil)
                } else {
                    cont.resume(returning: buffer)
                }
            }
        }
    }

    private static func loadViaImageManager(_ asset: PHAsset) async throws -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: error)
                    return
                }
                if (info?[PHImageCancelledKey] as? Bool) == true {
                    cont.resume(throwing: CancellationError())
                    return
                }
                // iCloud still downloading → degraded / nil without error.
                if (info?[PHImageResultIsInCloudKey] as? Bool) == true, data == nil {
                    cont.resume(throwing: LoadError.iCloudNotDownloaded)
                    return
                }
                cont.resume(returning: data)
            }
        }
    }

    // MARK: - Normalize

    static func normalizeToJPEG(_ raw: Data, quality: CGFloat = 0.88) throws -> Data {
        guard let image = UIImage(data: raw) else {
            throw LoadError.notAnImage
        }
        let maxEdge: CGFloat = 2400
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxEdge, longest > 0 {
            let scale = maxEdge / longest
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            scaled = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        } else {
            scaled = image
        }
        guard let jpeg = scaled.jpegData(compressionQuality: quality) else {
            throw LoadError.notAnImage
        }
        return jpeg
    }
}

// MARK: - Transferable image import (avoids public.png-only path)

struct PickedImageData: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        // File paths first — more reliable on Mac than raw NSItemProvider PNG export.
        FileRepresentation(importedContentType: .jpeg) { received in
            try Self.read(received.file)
        }
        FileRepresentation(importedContentType: .heic) { received in
            try Self.read(received.file)
        }
        FileRepresentation(importedContentType: .png) { received in
            try Self.read(received.file)
        }
        FileRepresentation(importedContentType: .image) { received in
            try Self.read(received.file)
        }
        DataRepresentation(importedContentType: .jpeg) { data in
            PickedImageData(data: data)
        }
        DataRepresentation(importedContentType: .heic) { data in
            PickedImageData(data: data)
        }
        DataRepresentation(importedContentType: .png) { data in
            PickedImageData(data: data)
        }
        DataRepresentation(importedContentType: .image) { data in
            PickedImageData(data: data)
        }
    }

    private static func read(_ url: URL) throws -> PickedImageData {
        let data = try Data(contentsOf: url)
        guard UIImage(data: data) != nil else {
            throw PhotosPickerMediaLoader.LoadError.notAnImage
        }
        return PickedImageData(data: data)
    }
}
