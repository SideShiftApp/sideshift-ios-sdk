import Foundation

/// What happened to one send.
enum SendResult: Equatable, Sendable {
    /// Accepted, or a duplicate the server already has.
    case delivered
    /// The server refused the event itself (bad payload, unknown key). Retrying would not help.
    case rejected
    /// Offline, rate limited or a server error. Kept and retried later.
    case retry
}

protocol Transport: Sendable {
    func send(_ event: AppEvent) async -> SendResult
}

private struct TransactionBody: Encodable {
    let installId: String
    let signedTransaction: String
    let consent: Bool
}

struct HTTPTransport: Transport {
    let endpoint: URL
    let appKey: String
    let session: URLSession

    func send(_ event: AppEvent) async -> SendResult {
        var url = endpoint.appendingPathComponent("api/commerce/app-sdk").appendingPathComponent(appKey)
        let body: Data?
        if event.eventType == .transaction {
            // Apple's signed transaction goes to its own endpoint, which checks the signature.
            url = url.appendingPathComponent("transactions")
            body = event.signedTransaction.flatMap { try? JSONEncoder().encode(TransactionBody(installId: event.installId, signedTransaction: $0, consent: event.consent)) }
        } else {
            body = try? JSONEncoder().encode(event)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        guard let body else { return .rejected }
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return .retry }
            switch status {
            case 200..<300: return .delivered
            case 429, 500...: return .retry
            default: return .rejected
            }
        } catch {
            return .retry
        }
    }
}
