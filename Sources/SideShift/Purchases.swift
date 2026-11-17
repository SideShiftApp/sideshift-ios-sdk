import Foundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Sends App Store purchases to SideShift as Apple signed them, so sales and subscription renewals are credited to the
/// creator with no server of your own. SideShift checks Apple's signature; nothing here can make up a purchase.
///
/// It watches `Transaction.updates` (renewals, refunds, purchases on other devices) and, at launch and each return to the
/// foreground, reads `Transaction.all` for purchases it has not sent. It never finishes a transaction: your app does.
final class PurchaseWatcher: @unchecked Sendable {
    private let store: InstallStore
    private let send: @Sendable (String, String) async -> Void
    private let lock = NSLock()
    private var listener: Task<Void, Never>?
    private static let sentKey = "com.sideshift.sdk.sentTransactions"

    /// - Parameter send: (transaction ID, signed transaction) to queue.
    init(store: InstallStore, send: @escaping @Sendable (String, String) async -> Void) {
        self.store = store
        self.send = send
    }

    /// Queues a signed transaction once per transaction ID and revocation (a refund re-sends it).
    func offer(id: String, revoked: Bool, signed: String) async {
        let key = revoked ? "\(id):revoked" : id
        guard markSent(key) else { return }
        await send(id, signed)
    }

    private func markSent(_ key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var sent = store.defaults.stringArray(forKey: Self.sentKey) ?? []
        guard !sent.contains(key) else { return false }
        sent.append(key)
        if sent.count > 500 { sent.removeFirst(sent.count - 500) }
        store.defaults.set(sent, forKey: Self.sentKey)
        return true
    }

    func start() {
        #if canImport(StoreKit)
        lock.lock(); defer { lock.unlock() }
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self, case .verified(let transaction) = update else { continue }
                await self.offer(id: String(transaction.id), revoked: transaction.revocationDate != nil, signed: update.jwsRepresentation)
            }
        }
        #endif
    }

    /// Reads every transaction on the device and queues the ones not sent yet.
    func scan() async {
        #if canImport(StoreKit)
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            await offer(id: String(transaction.id), revoked: transaction.revocationDate != nil, signed: result.jwsRepresentation)
        }
        #endif
    }
}
