import Foundation

/// File operations are explicit; callers serialize access to a given file.
public struct ProfileStore {
    public private(set) var profiles: [ProfileConfig] = []
    public private(set) var selectedID: UUID?
    public let fileURL: URL

    private struct Snapshot: Codable {
        let profiles: [ProfileConfig]
        let selectedID: UUID?
    }

    public init(fileURL: URL) { self.fileURL = fileURL }

    public mutating func load() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            profiles = []; selectedID = nil
            return
        }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
        profiles = snapshot.profiles
        selectedID = profiles.contains { $0.id == snapshot.selectedID } ? snapshot.selectedID : profiles.first?.id
    }

    public func save() throws {
        let data = try JSONEncoder().encode(Snapshot(profiles: profiles, selectedID: selectedID))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public mutating func add(_ profile: ProfileConfig) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        if selectedID == nil { selectedID = profile.id }
    }

    public mutating func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        if selectedID == id { selectedID = profiles.first?.id }
    }

    public mutating func select(id: UUID) {
        if profiles.contains(where: { $0.id == id }) { selectedID = id }
    }
}
