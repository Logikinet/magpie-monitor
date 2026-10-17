import MagpieKit

struct RefreshContext: Equatable {
    let profile: ProfileConfig?
    let isMockMode: Bool
    let isActive: Bool
    var filters: [String] = []
}
