import Foundation

public struct RoutePrompt: Decodable, Sendable {
    public let window: FlexibleInt?
    public let tokens: FlexibleInt?
    public let counted: Bool?
    public let turns: FlexibleInt?
    public let parts: LossyArray<PromptPart>?
}

