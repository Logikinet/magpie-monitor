import Foundation

public struct ProvidersEnvelope: Decodable, Sendable {
    public let providers: LossyArray<Provider>?
}

public struct Provider: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let icon: String?
    public let preset: String?
    public let host: String?
    public let website: String?
    public let routing: String?
    public let affinity: String?
    public let exposed: Bool?
    public let unlisted: Bool?
    public let noModels: Bool?
    public let ready: Bool?
    public let models: LossyArray<ProviderModel>?
    public let key: ProviderKey?
    public let account: ProviderAccount?
    public let agents: LossyArray<ProviderAgent>?
    public let activeModelsCount: FlexibleInt?
    enum CodingKeys: String, CodingKey {
        case id, name, icon, preset, host, website, routing, affinity, exposed, unlisted, noModels, ready, models, key, account, agents, off, chosen, fallback
        case activeModelsCount = "active_models_count"
    }
    public let off: Bool?
    public let chosen: LossyArray<String>?
    public let fallback: LossyArray<String>?
}

/// Only display metadata is decoded. Raw credential fields are deliberately ignored.
public struct ProviderKey: Decodable, Sendable {
    public let set: Bool?
    public let masked: String?
}

public struct ProviderAccount: Decodable, Sendable {
    public let user: String?
    public let plan: String?
    public let agent: String?
    public let agentName: String?
    public let agentIcon: String?
    public let logins: LossyArray<ProviderLogin>?
}

public struct ProviderLogin: Decodable, Sendable {
    public let agent: String?
    public let seen: MagpieDate?
    public let active: Bool?
    public let on: Bool?
    public let user: String?
    public let plan: String?
}

public struct ProviderAgent: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let icon: String?
    public let current: Bool?
}

public struct ProviderModel: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let on: Bool?
    public let context: FlexibleInt?
}

