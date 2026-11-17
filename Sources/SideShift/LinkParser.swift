import Foundation

/// Reads a SideShift tracking code and its click ID out of a URL the app opened or found on the pasteboard.
///
/// Two https shapes carry one, both written by the SideShift link page when the person taps through:
/// - The app's universal link: `https://<app website>/...?ss=<code>&ss_click=<click id>`.
/// - The link page itself, copied by its "Get the app" button: `https://<SideShift host>/a/<code>?c=<click id>`.
///   Only a link on the configured SideShift host counts, so another site's `/a/` path is ignored.
/// A code without a click ID is not a link: SideShift credits a link only with the click its page recorded.
enum LinkParser {
    static func click(from url: URL, sideShiftHost: String?) -> LinkClick? {
        guard url.scheme?.lowercased() == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        if let code = value("ss"), isCode(code), let clickId = value("ss_click"), isClickId(clickId) {
            return LinkClick(code: code, clickId: clickId)
        }
        if let host = components.host?.lowercased(), let sideShiftHost, host == sideShiftHost.lowercased() {
            let parts = components.path.split(separator: "/")
            if parts.count == 2, parts[0] == "a", isCode(String(parts[1])), let clickId = value("c"), isClickId(clickId) {
                return LinkClick(code: String(parts[1]), clickId: clickId)
            }
        }
        return nil
    }

    static func isCode(_ value: String) -> Bool { matches(value, #"^[A-Za-z0-9_-]{16,80}$"#) }
    static func isClickId(_ value: String) -> Bool { matches(value, #"^ss_clk_[A-Za-z0-9_-]{16,64}$"#) }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
