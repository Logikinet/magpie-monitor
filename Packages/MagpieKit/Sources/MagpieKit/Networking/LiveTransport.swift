import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct LiveTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // URLSession's async API propagates task cancellation on Darwin and Linux.
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MagpieError.network("服务器未返回 HTTP 响应")
        }
        return (data, response)
    }
}
