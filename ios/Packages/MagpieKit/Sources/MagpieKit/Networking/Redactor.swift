import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum Redactor {
    public static func redact(_ secret: String) -> String {
        "••••" + secret.suffix(2)
    }

    /// Deliberately excludes the request body and URL credentials/fragments.
    public static func requestDescription(_ request: URLRequest) -> String {
        var components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        components?.user = nil
        components?.password = nil
        components?.fragment = nil
        let queryItems = components?.queryItems?.map {
            URLQueryItem(name: $0.name, value: $0.name.lowercased() == "key" ? "••••" : $0.value)
        }
        components?.queryItems = queryItems
        let headers = (request.allHTTPHeaderFields ?? [:]).filter {
            !["authorization", "cookie"].contains($0.key.lowercased())
        }.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        return (["\(request.httpMethod ?? "GET") \(components?.string ?? "")"] + headers).joined(separator: "\n")
    }
}
