import Foundation

public struct Concurrency: Decodable {
    public let object: String?
    public let data: [String: Lane]?
    public let requests: FlexibleInt?
    public let waiting: FlexibleInt?
    public let tools: FlexibleInt?
    public let active: LossyArray<ActiveRequest>?
}

public struct Lane: Decodable {
    public let busy: FlexibleInt?
    public let waiting: FlexibleInt?
    public let limit: FlexibleInt?
}

public struct ActiveRequest: Decodable {
    public let session: String?
    public let route: FlexibleInt?
}
