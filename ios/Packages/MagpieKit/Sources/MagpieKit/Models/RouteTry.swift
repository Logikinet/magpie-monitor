import Foundation

public struct RouteTry: Decodable, Sendable {
    public let id: String?
    public let model: String?
    public let effort: String?
    public let start: MagpieDate?
    public let done: Bool?
    public let status: FlexibleInt?
    public let ms: FlexibleInt?
    public let ttft: FlexibleInt?
    public let firstText: FlexibleInt?
    public let flow: FlexibleInt?
    public let served: String?
}

