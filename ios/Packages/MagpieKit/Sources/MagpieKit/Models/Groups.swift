import Foundation

public struct GroupsEnvelope: Decodable, Sendable {
    public let groups: LossyArray<RoutingGroup>?
    public let pools: LossyArray<RoutingPool>?
}

public struct RoutingGroup: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let routing: String?
    public let affinity: String?
    public let members: LossyArray<String>?
    public let weights: [String: FlexibleDouble]?
    public let memberInfo: LossyArray<GroupMember>?
    public let ready: Bool?
}

public struct GroupMember: Decodable, Sendable {
    public let id: String?
    public let ready: Bool?
    public let provider: String?
    public let name: String?
    public let icon: String?
    public let model: String?
    public let on: FlexibleInt?
    public let of: String?
    public let efforts: LossyArray<String>?
    public let context: FlexibleInt?
    public let images: Bool?
    public let canFast: Bool?
    public let group: Bool?
    public let imagesUnknown: Bool?
}

public struct RoutingPool: Decodable, Sendable {
    public let provider: String?
    public let name: String?
    public let icon: String?
    public let kind: String?
    public let who: LossyArray<String>?
    public let routing: String?
    public let affinity: String?
}

