import Foundation

public struct SeatRest: Decodable, Sendable {
    public let why: String?
    public let status: FlexibleInt?
    public let until: MagpieDate?
    public let by: String?
    public let key: String?
    public let model: String?
}

