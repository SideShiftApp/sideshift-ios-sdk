#if canImport(SwiftUI) && os(iOS)
import SwiftUI

/// Apple's system Paste button, wired to SideShift. Put it in onboarding ("Tap to claim your creator's offer"): one tap
/// reads the link the SideShift link page copied, with no "Allow Paste" prompt, and credits the creator.
@available(iOS 16.0, *)
public struct SideShiftPasteButton: View {
    private let onResult: (Bool) -> Void

    /// - Parameter onResult: true when the pasted text was a SideShift link.
    public init(onResult: @escaping (Bool) -> Void = { _ in }) {
        self.onResult = onResult
    }

    public var body: some View {
        PasteButton(payloadType: String.self) { strings in
            let found = strings.contains { text in
                guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
                return SideShift.handle(url)
            }
            Task { @MainActor in onResult(found) }
        }
    }
}
#endif
