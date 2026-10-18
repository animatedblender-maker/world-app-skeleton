import AVFoundation
import Foundation

/// GET-only R2/S3 presigns return 403 on HEAD. AVPlayer probes with HEAD first, so hubs
/// playback must proxy through a custom scheme and answer with Range GET instead.
enum R2PresignedPlayback {
    static let urlScheme = "matterya-r2"

    static func needsProxy(_ url: URL) -> Bool {
        guard !MediaURLResolver.isBlockedR2PublicURL(url) else { return false }
        guard MediaURLResolver.looksLikeR2HostedURL(url) else { return false }
        return MediaURLResolver.isPresignedObjectURL(url)
    }

    static func assetURL(forPlayable url: URL) -> URL {
        guard needsProxy(url),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        comps.scheme = urlScheme
        return comps.url ?? url
    }

    static func httpsURL(from assetURL: URL) -> URL? {
        guard assetURL.scheme == urlScheme,
              var comps = URLComponents(url: assetURL, resolvingAgainstBaseURL: false)
        else { return nil }
        comps.scheme = "https"
        return comps.url
    }

    /// Retain the returned loader for the asset's lifetime (resourceLoader holds a weak delegate).
    static func makeAsset(for url: URL) -> (AVURLAsset, R2PresignedResourceLoader?) {
        let playURL = assetURL(forPlayable: url)
        let asset = AVURLAsset(
            url: playURL,
            options: [
                AVURLAssetAllowsCellularAccessKey: true,
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetAllowsConstrainedNetworkAccessKey: true,
            ]
        )
        if playURL.scheme == urlScheme {
            let loader = R2PresignedResourceLoader()
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            return (asset, loader)
        }
        return (asset, nil)
    }
}

final class R2PresignedResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    let queue = DispatchQueue(label: "matterya.r2.presigned.loader", qos: .userInitiated)

    private var tasks: [ObjectIdentifier: URLSessionDataTask] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let requestURL = loadingRequest.request.url,
              let https = R2PresignedPlayback.httpsURL(from: requestURL)
        else {
            loadingRequest.finishLoading(with: URLError(.badURL))
            return false
        }

        let id = ObjectIdentifier(loadingRequest)

        if loadingRequest.contentInformationRequest != nil, loadingRequest.dataRequest == nil {
            var req = URLRequest(url: https)
            req.httpMethod = "GET"
            req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            req.setValue("MatteryaHubs/1.0 (iOS; +https://matterya.com)", forHTTPHeaderField: "User-Agent")
            let task = session.dataTask(with: req) { [weak self] data, response, error in
                self?.queue.async {
                    self?.finishContentInfo(
                        loadingRequest,
                        id: id,
                        response: response,
                        data: data,
                        error: error
                    )
                }
            }
            tasks[id] = task
            task.resume()
            return true
        }

        guard let dataRequest = loadingRequest.dataRequest else {
            loadingRequest.finishLoading()
            return true
        }

        let lower = Int(dataRequest.currentOffset)
        let upper: Int
        if dataRequest.requestsAllDataToEndOfResource {
            // Cap chunk so we don't pull the whole file in one shot.
            upper = lower + 1_048_575
        } else {
            let requestedEnd = Int(dataRequest.requestedOffset) + dataRequest.requestedLength - 1
            upper = max(lower, requestedEnd)
        }

        var req = URLRequest(url: https)
        req.httpMethod = "GET"
        req.setValue("bytes=\(lower)-\(upper)", forHTTPHeaderField: "Range")
        req.setValue("MatteryaHubs/1.0 (iOS; +https://matterya.com)", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: req) { [weak self] data, response, error in
            self?.queue.async {
                self?.finishData(
                    loadingRequest,
                    dataRequest: dataRequest,
                    id: id,
                    response: response,
                    data: data,
                    error: error
                )
            }
        }
        tasks[id] = task
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let id = ObjectIdentifier(loadingRequest)
        queue.async { [weak self] in
            self?.tasks[id]?.cancel()
            self?.tasks[id] = nil
        }
    }

    private func finishContentInfo(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        id: ObjectIdentifier,
        response: URLResponse?,
        data: Data?,
        error: Error?
    ) {
        defer { tasks[id] = nil }
        if let error {
            loadingRequest.finishLoading(with: error)
            return
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            loadingRequest.finishLoading(with: URLError(.badServerResponse))
            return
        }
        applyContentInformation(loadingRequest.contentInformationRequest, http: http, fallbackBytes: data)
        loadingRequest.finishLoading()
    }

    private func finishData(
        _ loadingRequest: AVAssetResourceLoadingRequest,
        dataRequest: AVAssetResourceLoadingDataRequest,
        id: ObjectIdentifier,
        response: URLResponse?,
        data: Data?,
        error: Error?
    ) {
        defer { tasks[id] = nil }
        if let error {
            loadingRequest.finishLoading(with: error)
            return
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            loadingRequest.finishLoading(with: URLError(.badServerResponse))
            return
        }
        if loadingRequest.contentInformationRequest != nil {
            applyContentInformation(loadingRequest.contentInformationRequest, http: http, fallbackBytes: data)
        }
        if let data, !data.isEmpty {
            dataRequest.respond(with: data)
        }
        loadingRequest.finishLoading()
    }

    private func applyContentInformation(
        _ info: AVAssetResourceLoadingContentInformationRequest?,
        http: HTTPURLResponse,
        fallbackBytes: Data?
    ) {
        guard let info else { return }
        info.isByteRangeAccessSupported = true
        info.contentType = utiForMIME(http.mimeType) ?? http.mimeType ?? "public.mpeg-4"
        if let total = contentLength(from: http) {
            info.contentLength = total
        } else if let fallbackBytes {
            info.contentLength = Int64(fallbackBytes.count)
        }
    }

    private func contentLength(from http: HTTPURLResponse) -> Int64? {
        if let range = http.value(forHTTPHeaderField: "Content-Range"),
           let total = parseContentRangeTotal(range) {
            return total
        }
        // Only trust Content-Length when the response is a full-object 200 (not a 2-byte probe).
        if http.statusCode == 200,
           let raw = http.value(forHTTPHeaderField: "Content-Length"),
           let n = Int64(raw), n > 0 {
            return n
        }
        return nil
    }

    private func parseContentRangeTotal(_ raw: String) -> Int64? {
        // bytes 0-1/12345678
        guard let slash = raw.lastIndex(of: "/") else { return nil }
        let total = raw[raw.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        if total == "*" { return nil }
        return Int64(total)
    }

    private func utiForMIME(_ mime: String?) -> String? {
        switch (mime ?? "").lowercased() {
        case "video/mp4", "audio/mp4": return "public.mpeg-4"
        case "video/quicktime": return "com.apple.quicktime-movie"
        case "video/webm": return "org.webmproject.webm"
        case "image/webp": return "public.webp"
        default: return nil
        }
    }
}
