import Foundation

/// The kinds of event the SDK sends. They match the event types SideShift's app events API accepts.
public enum AppEventType: String, Codable, Sendable {
    case install = "app_install"
    case open = "app_open"
    case purchase = "checkout_completed"
    case custom
    case identify
    /// An App Store purchase, sent as Apple's signed transaction to the transactions endpoint.
    case transaction = "app_store_transaction"
}

/// The person's email and phone, each hashed on the device. SideShift never receives them in plain text.
struct HashedIdentity: Codable, Equatable, Sendable {
    var emailHash: String?
    var phoneHash: String?
    var instagramHash: String?
}

/// The SideShift link that opened the app: its tracking code, and the click the link page made.
public struct LinkClick: Codable, Equatable, Sendable {
    public let code: String
    public let clickId: String

    public init(code: String, clickId: String) {
        self.code = code
        self.clickId = clickId
    }
}

/// One event, as the SDK queues and sends it.
struct AppEvent: Codable, Equatable, Sendable {
    struct Properties: Codable, Equatable, Sendable {
        var eventName: String?
        var currency: String?
        var value: Double?
        var quantity: Int?
        var productName: String?
        var occurredAt: String?
        var sdkVersion: String?
        var appVersion: String?
        var osVersion: String?
    }

    let eventId: String
    let installId: String
    let eventType: AppEventType
    let consent: Bool
    var click: LinkClick?
    var promoCode: String?
    var identity: HashedIdentity?
    /// `.transaction` only: StoreKit 2's `jwsRepresentation`, which the server checks against Apple's signature.
    var signedTransaction: String?
    var orderId: String?
    var productId: String?
    var properties: Properties?
}
