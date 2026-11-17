import XCTest
@testable import SideShift

final class LinkParserTests: XCTestCase {
    let code = "ss_abcdefghijklmnopqrstuvwx"
    let clickId = "ss_clk_ABCDEFGHIJKLmnopqrst12"

    func testUniversalLinkCarriesCodeAndClick() {
        let url = URL(string: "https://brand.example/?ss=\(code)&ss_click=\(clickId)")!
        XCTAssertEqual(LinkParser.click(from: url, sideShiftHost: "app.sideshift.app"), LinkClick(code: code, clickId: clickId))
    }

    func testCopiedLinkPageOnSideShiftHost() {
        let url = URL(string: "https://app.sideshift.app/a/\(code)?c=\(clickId)")!
        XCTAssertEqual(LinkParser.click(from: url, sideShiftHost: "app.sideshift.app"), LinkClick(code: code, clickId: clickId))
    }

    func testLinkPageOnAnotherHostIsIgnored() {
        let url = URL(string: "https://evil.example/a/\(code)?c=\(clickId)")!
        XCTAssertNil(LinkParser.click(from: url, sideShiftHost: "app.sideshift.app"))
    }

    func testCodeWithoutAValidClickIdIsNotALink() {
        XCTAssertNil(LinkParser.click(from: URL(string: "https://brand.example/?ss=\(code)")!, sideShiftHost: nil))
        XCTAssertNil(LinkParser.click(from: URL(string: "https://brand.example/?ss=\(code)&ss_click=nope")!, sideShiftHost: nil))
        XCTAssertNil(LinkParser.click(from: URL(string: "https://app.sideshift.app/a/\(code)")!, sideShiftHost: "app.sideshift.app"))
    }

    func testOnlyHttpsLinksCount() {
        XCTAssertNil(LinkParser.click(from: URL(string: "brandapp://open?ss=\(code)&ss_click=\(clickId)")!, sideShiftHost: nil))
        XCTAssertNil(LinkParser.click(from: URL(string: "http://brand.example/?ss=\(code)&ss_click=\(clickId)")!, sideShiftHost: nil))
    }

    func testShortCodeIsNotALink() {
        XCTAssertNil(LinkParser.click(from: URL(string: "https://brand.example/?ss=short")!, sideShiftHost: nil))
    }
}

final class EventEncodingTests: XCTestCase {
    func testEncodesTheServerShapeWithoutNulls() throws {
        let event = AppEvent(eventId: "e1", installId: "ssi_0123456789abcdef", eventType: .install, consent: true,
                             click: LinkClick(code: "ss_abcdefghijklmnopqrstuvwx", clickId: "ss_clk_ABCDEFGHIJKLmnopqrst12"),
                             properties: .init(sdkVersion: "0.1.0"))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        XCTAssertEqual(json["eventType"] as? String, "app_install")
        XCTAssertEqual((json["click"] as? [String: Any])?["code"] as? String, "ss_abcdefghijklmnopqrstuvwx")
        XCTAssertEqual((json["click"] as? [String: Any])?["clickId"] as? String, "ss_clk_ABCDEFGHIJKLmnopqrst12")
        XCTAssertNil(json["orderId"])
        XCTAssertEqual(Set((json["properties"] as! [String: Any]).keys), ["sdkVersion"])
    }
}

private final class RecordingTransport: Transport, @unchecked Sendable {
    var results: [SendResult]
    let otherwise: SendResult
    var sent: [AppEvent] = []
    init(_ results: [SendResult], otherwise: SendResult = .delivered) { self.results = results; self.otherwise = otherwise }
    func send(_ event: AppEvent) async -> SendResult {
        sent.append(event)
        return results.isEmpty ? otherwise : results.removeFirst()
    }
}

private struct FixedPasteboard: PasteboardReading {
    let link: LinkClick?
    func sideShiftLink(host: String?) async -> LinkClick? { link }
}

final class ClientTests: XCTestCase {
    private func makeStore() -> InstallStore {
        let suite = "sideshift-tests-\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        return InstallStore(defaults: UserDefaults(suiteName: suite)!, directory: directory)
    }

    func testFirstOpenSendsOneInstallWithThePastedLink() async {
        let store = makeStore()
        let transport = RecordingTransport([])
        let click = LinkClick(code: "ss_abcdefghijklmnopqrstuvwx", clickId: "ss_clk_ABCDEFGHIJKLmnopqrst12")
        let client = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: "app.sideshift.app",
                            options: .init(sendsPurchases: false), pasteboard: FixedPasteboard(link: click))
        await client.start()
        XCTAssertEqual(transport.sent.map(\.eventType), [.install])
        XCTAssertEqual(transport.sent.first?.click, click)
        XCTAssertEqual(transport.sent.first?.installId, store.installId)

        // A later launch is an open, not a second install, and is throttled.
        let again = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: nil,
                           options: .init(sendsPurchases: false), pasteboard: FixedPasteboard(link: click))
        await again.start()
        XCTAssertEqual(transport.sent.map(\.eventType), [.install])
    }

    func testFailedSendStaysQueuedAndRejectedIsDropped() async {
        let store = makeStore()
        let transport = RecordingTransport([.retry])
        let queue = EventQueue(store: store, transport: transport)
        let event = AppEvent(eventId: "e1", installId: store.installId, eventType: .open, consent: true)
        await queue.enqueue(event)
        let stillQueued = await queue.pending
        XCTAssertEqual(stillQueued, [event])
        XCTAssertEqual(store.loadQueue(), [event], "kept on disk for the next launch")

        let rejecting = RecordingTransport([.rejected])
        let next = EventQueue(store: store, transport: rejecting)
        await next.flush()
        let left = await next.pending
        XCTAssertEqual(left, [])
    }

    func testWithdrawingConsentDropsQueuedEventsAndSendsOnlyTheWithdrawal() async {
        let store = makeStore()
        let transport = RecordingTransport([], otherwise: .retry)
        let queue = EventQueue(store: store, transport: transport)
        let client = Client(store: store, queue: queue, sideShiftHost: nil, options: .init(), pasteboard: FixedPasteboard(link: nil))
        await client.send(.custom, properties: .init(eventName: "Signup"))
        await client.setConsent(false)
        let pending = await queue.pending
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.consent, false)
        XCTAssertEqual(pending.first?.properties?.eventName, "ConsentWithdrawn")
        await client.send(.custom, properties: .init(eventName: "Ignored"))
        let after = await queue.pending
        XCTAssertEqual(after.count, 1)
    }
}

final class IdentityTests: XCTestCase {
    func testEmailIsTrimmedLowercasedAndHashed() {
        XCTAssertEqual(IdentityHasher.email("  Jane@Example.COM "), IdentityHasher.sha256("jane@example.com"))
        XCTAssertEqual(IdentityHasher.sha256("jane@example.com"), "8c87b489ce35cf2e2f39f80e282cb2e804932a56a213983eeeb428407d43b52d")
        XCTAssertNil(IdentityHasher.email("not an email"))
    }

    func testPhoneKeepsDigitsWithCountryCode() {
        XCTAssertEqual(IdentityHasher.phone("+1 (650) 555-0100"), IdentityHasher.sha256("16505550100"))
        XCTAssertNil(IdentityHasher.phone("123"))
    }

    func testPromoCodesAreUppercasedAndChecked() {
        XCTAssertEqual(PromoCode.normalized(" jane20 "), "JANE20")
        XCTAssertNil(PromoCode.normalized("no spaces"))
        XCTAssertNil(PromoCode.normalized("ab"))
    }

    func testIdentifyEventCarriesOnlyHashes() throws {
        let event = AppEvent(eventId: "e1", installId: "ssi_0123456789abcdef", eventType: .identify, consent: true,
                             identity: HashedIdentity(emailHash: IdentityHasher.email("jane@example.com"), phoneHash: nil))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        XCTAssertEqual(json["eventType"] as? String, "identify")
        XCTAssertEqual(json["identity"] as? [String: String], ["emailHash": "8c87b489ce35cf2e2f39f80e282cb2e804932a56a213983eeeb428407d43b52d"])
    }
}

final class InstagramAndPurchaseTests: XCTestCase {
    func testInstagramUsernamesAreNormalizedBeforeHashing() {
        let expected = IdentityHasher.sha256("jane.doe_1")
        XCTAssertEqual(IdentityHasher.instagram("@Jane.Doe_1"), expected)
        XCTAssertEqual(IdentityHasher.instagram(" https://www.instagram.com/jane.doe_1/?hl=en "), expected)
        XCTAssertNil(IdentityHasher.instagram("not a username!"))
    }

    func testEachTransactionIsQueuedOnceAndAgainWhenRefunded() async {
        let suite = "sideshift-tests-\(UUID().uuidString)"
        let store = InstallStore(defaults: UserDefaults(suiteName: suite)!, directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let sent = SentLog()
        let watcher = PurchaseWatcher(store: store) { id, signed in await sent.add("\(id)|\(signed)") }
        await watcher.offer(id: "2000001", revoked: false, signed: "jws-a")
        await watcher.offer(id: "2000001", revoked: false, signed: "jws-a")
        await watcher.offer(id: "2000001", revoked: true, signed: "jws-b")
        let log = await sent.items
        XCTAssertEqual(log, ["2000001|jws-a", "2000001|jws-b"])
    }

    func testTransactionEventsCarryOnlyTheSignedTransaction() throws {
        let event = AppEvent(eventId: "e", installId: "ssi_0123456789abcdef", eventType: .transaction, consent: true, signedTransaction: "a.b.c")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as! [String: Any]
        XCTAssertEqual(json["eventType"] as? String, "app_store_transaction")
        XCTAssertEqual(json["signedTransaction"] as? String, "a.b.c")
    }
}

private actor SentLog {
    var items: [String] = []
    func add(_ item: String) { items.append(item) }
}

private struct FixedTracking: TrackingPermission {
    let isAuthorized: Bool
}

final class TrackingPermissionTests: XCTestCase {
    private func makeStore() -> InstallStore {
        let suite = "sideshift-tests-\(UUID().uuidString)"
        return InstallStore(defaults: UserDefaults(suiteName: suite)!, directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
    }

    func testIdentityWaitsForTrackingPermissionAndKeepsOnlyHashes() async {
        let store = makeStore()
        let transport = RecordingTransport([])
        let identity = HashedIdentity(emailHash: IdentityHasher.email("jane@example.com"), phoneHash: nil, instagramHash: nil)
        let denied = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: nil,
                            options: .init(sendsPurchases: false), pasteboard: FixedPasteboard(link: nil), tracking: FixedTracking(isAuthorized: false))
        await denied.identify(identity)
        XCTAssertTrue(transport.sent.isEmpty)
        XCTAssertEqual(store.pendingIdentity, identity)

        let allowed = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: nil,
                             options: .init(sendsPurchases: false), pasteboard: FixedPasteboard(link: nil), tracking: FixedTracking(isAuthorized: true))
        await allowed.sendPendingIdentity()
        XCTAssertEqual(transport.sent.map(\.eventType), [.identify])
        XCTAssertNil(store.pendingIdentity)
    }

    func testAppsCanSendIdentityWithoutTheTrackingPrompt() async {
        let store = makeStore()
        let transport = RecordingTransport([])
        let client = Client(store: store, queue: EventQueue(store: store, transport: transport), sideShiftHost: nil,
                            options: .init(sendsPurchases: false, identityNeedsTrackingPermission: false), pasteboard: FixedPasteboard(link: nil),
                            tracking: FixedTracking(isAuthorized: false))
        await client.identify(HashedIdentity(emailHash: nil, phoneHash: nil, instagramHash: IdentityHasher.instagram("@jane")))
        XCTAssertEqual(transport.sent.map(\.eventType), [.identify])
    }
}
