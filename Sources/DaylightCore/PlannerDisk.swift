import Foundation
import Darwin

/// One writer per data directory. The lock is held until the object is released.
public final class PlannerDisk {
    public let directory: URL
    public var file: URL { directory.appendingPathComponent("planner.json") }
    public var backup: URL { directory.appendingPathComponent("planner.previous.json") }
    private var lock: Int32 = -1
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lock = Darwin.open(directory.appendingPathComponent(".writer.lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw PlannerError.unavailableDirectory }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(lock); lock = -1; throw PlannerError.alreadyOpen }
    }
    deinit { if lock >= 0 { flock(lock, LOCK_UN); Darwin.close(lock) } }
    public static func decode(_ data: Data) throws -> Planner {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let planner = try decoder.decode(Planner.self, from: data)
        try planner.validate()
        return planner
    }
    public static func encode(_ planner: Planner) throws -> Data {
        try planner.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(planner)
    }
    public func load() throws -> Planner {
        guard FileManager.default.fileExists(atPath: file.path) else { return Planner() }
        let data = try Data(contentsOf: file)
        let planner = try Self.decode(data)
        if (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["schemaVersion"] as? Int == 1 {
            try save(planner)
        }
        return planner
    }
    public func save(_ planner: Planner) throws {
        let data = try Self.encode(planner)
        if FileManager.default.fileExists(atPath: file.path) {
            let old = try Data(contentsOf: file)
            _ = try Self.decode(old) // Never overwrite a corrupt original silently.
            if (try? JSONSerialization.jsonObject(with: old) as? [String: Any])?["schemaVersion"] as? Int == 1 {
                let archive = directory.appendingPathComponent("planner.before-v2.json")
                if !FileManager.default.fileExists(atPath: archive.path) { try writePrivate(old, to: archive) }
            }
            try writePrivate(old, to: backup)
        }
        try writePrivate(data, to: file)
    }
    /// An explicit restore preserves the old bytes, including an unreadable original.
    @discardableResult public func restore(_ data: Data) throws -> Planner {
        let incoming = try Self.decode(data)
        let encoded = try Self.encode(incoming)
        if FileManager.default.fileExists(atPath: file.path) {
            let preserved = directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try writePrivate(Data(contentsOf: file), to: preserved)
        }
        try writePrivate(encoded, to: file)
        return incoming
    }
    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
