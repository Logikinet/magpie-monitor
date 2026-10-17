import Foundation

public struct PromptItem: Decodable, Sendable {
    public let name: String?
    public let tokens: FlexibleInt?
    public let tag: String?
}

