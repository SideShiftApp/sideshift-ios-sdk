import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// The SideShift App SDK: credits installs and in-app activity to the creator whose SideShift link brought the person in.
///
/// ```swift
/// SideShift.configure(appKey: "ss_pixel_…")
/// // SwiftUI: .onOpenURL { SideShift.handle($0) }
/// SideShift.track("CompleteRegistration")
/// // Your server sends each paid order to the Orders API with visitorId = SideShift.installId.
/// ```
///
/// How an install is tied to a link: a creator's link opens the SideShift link page, whose "Get the app" button copies
/// the link and opens the App Store. On first open the SDK reads that link from the pasteboard (iOS may ask the person to
/// allow the paste). When the app is already installed, the page opens the app's universal link instead, which you pass
/// to `handle(_:)`. The SDK uses no advertising ID and no device fingerprint.
public enum SideShift {
    public static let sdkVersion = "0.1.0"

    /// Options for `configure`.
    public struct Options: Sendable {
        /// Read a SideShift link from the pasteboard on the first open after install. On by default: it is how a new
        /// install finds the link that sent it.
        public var readsPasteboardOnInstall: Bool
        /// Send `app_open` when the app comes to the foreground, at most once per this many seconds.
        public var openInterval: TimeInterval
        /// Send App Store purchases, renewals and refunds (Apple-signed) so they are credited to the creator. On by default.
        public var sendsPurchases: Bool
        /// Send `identify` (hashed email, phone, Instagram username) only once the person allows tracking in Apple's App
        /// Tracking Transparency prompt. On by default: matching them with what a person gave a creator's link page or
        /// SideChat DM links your app's data with SideShift's for measurement, which Apple's rules call tracking. Until
        /// then the SDK keeps the latest identity on the device and sends it when permission is granted. Turn this off
        /// only if your own App Store privacy review concludes otherwise.
        public var identityNeedsTrackingPermission: Bool

        public init(readsPasteboardOnInstall: Bool = true, openInterval: TimeInterval = 30 * 60, sendsPurchases: Bool = true,
                    identityNeedsTrackingPermission: Bool = true) {
            self.readsPasteboardOnInstall = readsPasteboardOnInstall
            self.openInterval = openInterval
            self.sendsPurchases = sendsPurchases
            self.identityNeedsTrackingPermission = identityNeedsTrackingPermission
        }
    }

    private static let state = SDKState()

    /// Starts the SDK. Call once, as early in launch as you can.
    /// - Parameters:
    ///   - appKey: The app's SDK key from SideShift (Integrations → SideShift App SDK → Tracking).
    ///   - endpoint: The SideShift origin. Leave the default unless SideShift gives you another.
    public static func configure(appKey: String, endpoint: URL = URL(string: "https://app.sideshift.app")!, options: Options = Options()) {
        let store = InstallStore()
        let transport = HTTPTransport(endpoint: endpoint, appKey: appKey, session: .shared)
        let client = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: endpoint.host, options: options)
        guard state.set(client) else { return }
        Task { await client.start() }
    }

    /// The per-install ID. Send it to your server with each order, as the Orders API's `visitorId`.
    public static var installId: String { state.client?.store.installId ?? InstallStore().installId }

    /// Pass every URL the app opens: SwiftUI `onOpenURL`, `scene(_:openURLContexts:)` or a universal link's
    /// `webpageURL`. Returns true when the URL was a SideShift link (an https URL with the link page's code and click ID).
    @discardableResult
    public static func handle(_ url: URL) -> Bool {
        guard let client = state.client, let click = LinkParser.click(from: url, sideShiftHost: client.sideShiftHost) else { return false }
        Task { await client.opened(from: click) }
        return true
    }

    /// Tells SideShift who the person is, at sign-up or log-in. The email and phone are hashed on the device. If the person
    /// gave the same email on a creator's link page in the last 7 days, the install is credited to that creator, with no
    /// link tap or paste needed.
    ///
    /// `instagram` is the person's Instagram username (with or without @). If a creator's SideChat DM went to that account
    /// in the last 7 days, the install is credited to that creator, with no email needed.
    public static func identify(email: String? = nil, phone: String? = nil, instagram: String? = nil) {
        guard let client = state.client else { return }
        let identity = HashedIdentity(emailHash: email.flatMap(IdentityHasher.email), phoneHash: phone.flatMap(IdentityHasher.phone),
                                      instagramHash: instagram.flatMap(IdentityHasher.instagram))
        guard identity.emailHash != nil || identity.phoneHash != nil || identity.instagramHash != nil else { return }
        Task { await client.identify(identity) }
    }

    /// Credits the creator whose code the person typed, such as JANE20. Returns false for text that cannot be a code;
    /// SideShift itself checks that the code belongs to one of your creators.
    @discardableResult
    public static func applyCode(_ code: String) -> Bool {
        guard let client = state.client, let code = PromoCode.normalized(code) else { return false }
        Task { await client.send(.open, promoCode: code) }
        return true
    }

    /// Sends a custom event, such as `CompleteRegistration` or `Subscribe`.
    /// - Parameter eventId: Pass your own ID when your server will send the same event, so SideShift counts it once.
    public static func track(_ name: String, value: Double? = nil, currency: String? = nil, eventId: String = UUID().uuidString) {
        guard let client = state.client else { return }
        Task { await client.send(.custom, eventId: eventId, properties: .init(eventName: name, currency: currency, value: value)) }
    }

    /// Sends a purchase made in the app. It shows the sale in SideShift; the creator's commission comes from the order
    /// your server sends to the Orders API with the same `orderId`.
    public static func trackPurchase(orderId: String, value: Double, currency: String, productId: String? = nil, quantity: Int? = nil) {
        guard let client = state.client else { return }
        Task {
            await client.send(.purchase, eventId: "purchase:\(orderId)", orderId: orderId, productId: productId,
                              properties: .init(currency: currency, value: value, quantity: quantity))
        }
    }

    #if canImport(StoreKit)
    /// Sends a purchase right after `product.purchase()`, instead of waiting for the next launch or foreground.
    /// The SDK sends App Store purchases on its own; this only makes it sooner.
    public static func track(_ result: VerificationResult<Transaction>) {
        guard let client = state.client, case .verified(let transaction) = result else { return }
        let signed = result.jwsRepresentation
        Task { await client.purchases.offer(id: String(transaction.id), revoked: transaction.revocationDate != nil, signed: signed) }
    }
    #endif

    /// Records the person's choice. With `false` the SDK stops sending, drops what it has queued and tells SideShift,
    /// which stops using this install's events for attribution.
    public static func setConsent(_ granted: Bool) {
        guard let client = state.client else { return }
        Task { await client.setConsent(granted) }
    }

    /// Sends queued events now.
    public static func flush() {
        guard let client = state.client else { return }
        Task { await client.queue.flush() }
    }
}

/// Holds the one configured client.
private final class SDKState: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Client?
    var client: Client? { lock.lock(); defer { lock.unlock() }; return current }
    func set(_ client: Client) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard current == nil else { return false }
        current = client
        return true
    }
}

/// The configured SDK: builds events and decides when to send them.
actor Client {
    nonisolated let store: InstallStore
    nonisolated let queue: EventQueue
    nonisolated let sideShiftHost: String?
    private let options: SideShift.Options
    private let pasteboard: PasteboardReading
    private var observer: NSObjectProtocol?
    nonisolated let purchases: PurchaseWatcher
    private let tracking: TrackingPermission

    init(store: InstallStore, queue: EventQueue, sideShiftHost: String?, options: SideShift.Options, pasteboard: PasteboardReading = SystemPasteboard(),
         tracking: TrackingPermission = SystemTrackingPermission()) {
        self.tracking = tracking
        self.store = store
        self.queue = queue
        self.sideShiftHost = sideShiftHost
        self.options = options
        self.pasteboard = pasteboard
        let installId = store.installId
        self.purchases = PurchaseWatcher(store: store) { [queue] _, signed in
            guard store.consent else { return }
            await queue.enqueue(AppEvent(eventId: UUID().uuidString, installId: installId, eventType: .transaction, consent: true, signedTransaction: signed))
        }
    }

    func start() async {
        await queue.flush()
        if !store.installSent {
            let click = options.readsPasteboardOnInstall ? await pasteboard.sideShiftLink(host: sideShiftHost) : nil
            store.installSent = true
            store.lastOpen = Date()
            await send(.install, click: click)
        } else {
            await foregrounded()
        }
        await observeForeground()
        await sendPendingIdentity()
        if options.sendsPurchases {
            purchases.start()
            await purchases.scan()
        }
    }

    /// The app came to the foreground: an open, unless one was sent recently.
    func foregrounded() async {
        // The person may have allowed tracking in Settings while the app was in the background.
        await sendPendingIdentity()
        if let last = store.lastOpen, Date().timeIntervalSince(last) < options.openInterval { return }
        store.lastOpen = Date()
        await send(.open)
        if options.sendsPurchases { await purchases.scan() }
    }

    /// The app opened from a SideShift link: always an open, carrying the link.
    func opened(from click: LinkClick) async {
        store.lastOpen = Date()
        await send(.open, click: click)
    }

    /// Sends the identity now, or keeps it until the person allows tracking (see `identityNeedsTrackingPermission`).
    func identify(_ identity: HashedIdentity) async {
        if options.identityNeedsTrackingPermission && !tracking.isAuthorized {
            store.pendingIdentity = identity
            return
        }
        store.pendingIdentity = nil
        await send(.identify, identity: identity)
    }

    /// Sends an identity kept for tracking permission once the person has granted it.
    func sendPendingIdentity() async {
        guard let pending = store.pendingIdentity, !options.identityNeedsTrackingPermission || tracking.isAuthorized else { return }
        store.pendingIdentity = nil
        await send(.identify, identity: pending)
    }

    func setConsent(_ granted: Bool) async {
        let was = store.consent
        store.consent = granted
        guard was && !granted else { return }
        await queue.dropConsentedEvents()
        await queue.enqueue(AppEvent(eventId: "consent:\(store.installId):\(UUID().uuidString)", installId: store.installId,
                                     eventType: .custom, consent: false,
                                     properties: .init(eventName: "ConsentWithdrawn", sdkVersion: SideShift.sdkVersion)))
    }

    func send(_ type: AppEventType, eventId: String = UUID().uuidString, click: LinkClick? = nil, promoCode: String? = nil,
              identity: HashedIdentity? = nil, orderId: String? = nil, productId: String? = nil,
              properties: AppEvent.Properties = .init()) async {
        guard store.consent else { return }
        var properties = properties
        properties.occurredAt = ISO8601DateFormatter().string(from: Date())
        properties.sdkVersion = SideShift.sdkVersion
        properties.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        properties.osVersion = ProcessInfo.processInfo.operatingSystemVersionString.prefix(40).description
        await queue.enqueue(AppEvent(eventId: eventId, installId: store.installId, eventType: type, consent: true,
                                     click: click, promoCode: promoCode, identity: identity, orderId: orderId, productId: productId,
                                     properties: properties))
    }

    private func observeForeground() async {
        #if canImport(UIKit) && !os(watchOS)
        guard observer == nil else { return }
        observer = await MainActor.run {
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { await self.foregrounded() }
            }
        }
        #endif
    }
}

/// Reads a SideShift link from the pasteboard, once, on the first open.
protocol PasteboardReading: Sendable {
    func sideShiftLink(host: String?) async -> LinkClick?
}

struct SystemPasteboard: PasteboardReading {
    func sideShiftLink(host: String?) async -> LinkClick? {
        #if canImport(UIKit) && os(iOS)
        // Checking for a URL pattern does not read the pasteboard or ask the person. Only a likely URL is read.
        let patterns = try? await UIPasteboard.general.detectedPatterns(for: [\.probableWebURL])
        guard patterns?.contains(\.probableWebURL) == true else { return nil }
        let text = await MainActor.run { UIPasteboard.general.string }
        guard let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return LinkParser.click(from: url, sideShiftHost: host)
        #else
        return nil
        #endif
    }
}
