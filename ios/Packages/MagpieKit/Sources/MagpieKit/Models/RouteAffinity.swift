import Foundation

public struct RouteAffinity: Decodable, Sendable {
    public let mode: String?
    public let turn: FlexibleInt?
    public let within: Bool?
    public let last: String?
    public let lastTurn: FlexibleInt?
    public let at: MagpieDate?
    public let cacheRead: FlexibleInt?
    public let cacheWrite: FlexibleInt?
    public let kept: Bool?
    public let why: String?
}

