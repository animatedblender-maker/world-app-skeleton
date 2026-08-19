import Foundation

/// URLSession helpers that **do not** participate in Swift cooperative cancellation.
///
/// SwiftUI `.task(id:)` cancels the previous task when the id changes. That was
/// aborting `/v1/feed`, hubs for-you, and Sparks GraphQL mid-flight on every
/// cold launch (gen 0 → warmup bumps generation → `cancelled` → empty catalogs).
enum UncancellableHTTP {
    /// Fire-and-forget data task — survives parent `Task` cancellation.
    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}
