import Foundation

public struct PromptPart: Decodable, Sendable {
    public let kind: String?
    public let tokens: FlexibleInt?
    public let items: LossyArray<PromptItem>?
}

