import Foundation

/// What the SDK keeps on the device: the install ID, whether the install was sent, consent, and the queued events.
/// The install ID is random and per install. It is not the advertising ID and is never shared with other apps.
final class InstallStore: @unchecked Sendable {
    let defaults: UserDefaults
    private let queueURL: URL
    private let lock = NSLock()

    private enum Key {
        static let installId = "com.sideshift.sdk.installId"
        static let installSent = "com.sideshift.sdk.installSent"
        static let consent = "com.sideshift.sdk.consent"
        static let lastOpen = "com.sideshift.sdk.lastOpen"
        static let pendingIdentity = "com.sideshift.sdk.pendingIdentity"
    }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SideShift", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        queueURL = base.appendingPathComponent("events.json")
    }

    var installId: String {
        lock.lock(); defer { lock.unlock() }
        if let existing = defaults.string(forKey: Key.installId), LinkParser.isCode(existing) { return existing }
        let created = "ssi_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        defaults.set(created, forKey: Key.installId)
        return created
    }

    var installSent: Bool {
        get { defaults.bool(forKey: Key.installSent) }
        set { defaults.set(newValue, forKey: Key.installSent) }
    }

    var consent: Bool {
        get { defaults.object(forKey: Key.consent) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.consent) }
    }

    var lastOpen: Date? {
        get { defaults.object(forKey: Key.lastOpen) as? Date }
        set { defaults.set(newValue, forKey: Key.lastOpen) }
    }

    /// An identity waiting for tracking permission: hashes only, never the email, phone or username.
    var pendingIdentity: HashedIdentity? {
        get { defaults.data(forKey: Key.pendingIdentity).flatMap { try? JSONDecoder().decode(HashedIdentity.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.pendingIdentity) }
    }

    func loadQueue() -> [AppEvent] {
        guard let data = try? Data(contentsOf: queueURL) else { return [] }
        return (try? JSONDecoder().decode([AppEvent].self, from: data)) ?? []
    }

    func saveQueue(_ events: [AppEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }
}
