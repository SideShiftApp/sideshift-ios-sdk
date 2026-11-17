import Foundation
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// Whether the person allowed tracking in Apple's App Tracking Transparency prompt. The SDK never shows the prompt: your
/// app decides when to ask, with `ATTrackingManager.requestTrackingAuthorization`.
protocol TrackingPermission: Sendable {
    var isAuthorized: Bool { get }
}

struct SystemTrackingPermission: TrackingPermission {
    var isAuthorized: Bool {
        #if canImport(AppTrackingTransparency) && os(iOS)
        return ATTrackingManager.trackingAuthorizationStatus == .authorized
        #else
        return false
        #endif
    }
}
