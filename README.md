# SideShift App SDK for iOS

<p align="center">
  <img src="assets/logo.png" alt="SideShift" width="112" />
</p>

Credit app installs, sign-ups and App Store revenue to the creator who brought each person in. This is the iOS SDK
for brands that run creator campaigns and SideChat (comment-to-DM) on [SideShift](https://sideshift.app): it does for
your app what the SideShift Pixel does for a website.

- **Installs from creator links.** A creator's link opens a SideShift page that sends the person to the App Store. On the
  first open, the SDK ties the install to that link.
- **People, not devices.** If a person gave their email in a creator's SideChat DM or on the link page, or a SideChat DM
  went to their Instagram account, their sign-up is credited to that creator, on any device.
- **Revenue Apple signed.** App Store purchases, renewals and refunds are sent as Apple signed them and checked by
  SideShift. No server of your own is needed.
- **Exact, never guessed.** No advertising identifier and no device fingerprinting.

## Contents

- [Requirements](#requirements)
- [1. Add your app in SideShift](#1-add-your-app-in-sideshift)
- [2. Install the package](#2-install-the-package)
- [3. Start the SDK](#3-start-the-sdk)
- [4. Pass the links your app opens](#4-pass-the-links-your-app-opens)
- [5. Identify people at sign-up](#5-identify-people-at-sign-up)
- [6. App Store purchases and renewals](#6-app-store-purchases-and-renewals)
- [Optional: Paste button, creator codes and events](#optional-paste-button-creator-codes-and-events)
- [From your server](#from-your-server)
- [How a creator gets credit](#how-a-creator-gets-credit)
- [Privacy](#privacy)
- [Test your setup](#test-your-setup)
- [API reference](#api-reference)

## Requirements

- iOS 15 or later (the Paste button needs iOS 16)
- Swift 5.9 or later, Xcode 15 or later
- A SideShift brand account with SideChat or creator campaigns

## 1. Add your app in SideShift

In SideShift, open **Settings → Ads & Ecom**, find **SideShift App SDK** and choose **Add App**. Paste your App Store link:
SideShift fills in the app name, App Store ID, bundle ID and website.

SideShift then shows:

| Key | Looks like | Where it goes |
|---|---|---|
| SDK key | `ss_pixel_…` | In your app. It is public, like a pixel code. |
| Orders API key | `ss_orders_…` | Only on your server. Keep it secret. |

The app's **Setup** tab walks through every step below and shows a green check as each one starts working.

## 2. Install the package

In Xcode, choose **File → Add Package Dependencies**, enter this repository's URL and add the **SideShift** library to
your app target:

```text
https://github.com/SideShiftApp/sideshift-ios-sdk
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/SideShiftApp/sideshift-ios-sdk", from: "0.1.0")
```

## 3. Start the SDK

Call `configure` once, as early in launch as you can.

**SwiftUI**

```swift
import SideShift
import SwiftUI

@main
struct ExampleApp: App {
    init() {
        SideShift.configure(appKey: "YOUR_SDK_KEY")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { SideShift.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { SideShift.handle(url) }
                }
        }
    }
}
```

**UIKit**

```swift
import SideShift

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    SideShift.configure(appKey: "YOUR_SDK_KEY")
    return true
}
```

From then on the SDK sends `app_install` on the first open and `app_open` when the app comes back to the foreground.
Events wait on the device while it is offline and are retried.

## 4. Pass the links your app opens

Give the SDK every URL your app opens. It ignores anything that is not a SideShift link.

```swift
// SwiftUI: .onOpenURL and .onContinueUserActivity, as above.

// UIKit, scene delegate
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL { SideShift.handle(url) }
}
func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
    contexts.forEach { SideShift.handle($0.url) }
}
```

When someone who already has your app taps **I already have it** on the link page, SideShift opens your website with
`ss` and `ss_click` in the URL. With [universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)
set up for that domain, iOS opens your app instead, and `handle` credits the creator.

## 5. Identify people at sign-up

When a person signs up or logs in, tell SideShift who they are. The SDK hashes each value on the device; SideShift never
receives them in plain text.

```swift
SideShift.identify(email: user.email, phone: user.phone, instagram: user.instagramUsername)
```

Pass whichever you have. If the same person gave that email in a creator's SideChat DM or on the link page, or a SideChat
DM went to that Instagram account, in the last 7 days, the install is credited to that creator. This is how SideShift
matches people who never tapped the link on this phone.

By default, the SDK sends `identify` only after the person allows tracking in Apple's App Tracking Transparency prompt;
until then it keeps the latest hashes on the device. See [Privacy](#privacy).

## 6. App Store purchases and renewals

**Nothing to call.** The SDK sends every App Store purchase it sees, as Apple signed it: purchases, purchases on other
devices, renewals and refunds. SideShift checks Apple's signature and your bundle ID. To send a purchase at once instead
of at the next launch:

```swift
let result = try await product.purchase()
if case .success(let verification) = result {
    SideShift.track(verification)
    // ...unlock content and finish the transaction as usual
}
```

The SDK never finishes transactions; your app does.

**Renewals while the app is closed.** In App Store Connect, open your app → **App Information** → **App Store Server
Notifications**, choose **Version 2**, and set the production URL to:

```text
https://app.sideshift.app/api/commerce/app-store-notifications
```

If that URL is already taken by another service (RevenueCat, for example), forward its App Store notifications to the
SideShift URL instead.

Sandbox and TestFlight purchases are recorded as test purchases and earn no commission.

## Optional: Paste button, creator codes and events

**Paste button.** The link page copies the creator's link. The SDK reads it on the first open, which can show iOS's
"Allow Paste" prompt. Apple's own Paste button reads it with no prompt. Put it in onboarding:

```swift
Text("Came from a creator? Tap to claim their offer.")
SideShiftPasteButton { found in
    // found is true when the pasted text was a SideShift link
}
```

**Creator codes.** In SideShift you can give a creator's link a code such as `JANE20`. If your app has a code field:

```swift
SideShift.applyCode(codeField.text ?? "")
```

**Events.** Track any step you want to see per creator:

```swift
SideShift.track("CompleteRegistration")
SideShift.track("StartTrial", value: 0, currency: "USD")
```

## From your server

Two endpoints take your **Orders API key**. Send the install ID from the app (`SideShift.installId`) with each request.

**Orders** (revenue that does not go through the App Store, for example web checkout):

```bash
curl https://app.sideshift.app/api/commerce/orders \
  -H "Authorization: Bearer YOUR_ORDERS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "orderId": "order_123",
    "totalCents": 999,
    "currency": "USD",
    "occurredAt": "2026-11-17T18:00:00Z",
    "visitorId": "INSTALL_ID"
  }'
```

For an App Store purchase, use Apple's transaction ID as `orderId`, so SideShift counts it once.

**Events** (an approval, a payout, a renewal you process yourself):

```bash
curl https://app.sideshift.app/api/commerce/app-events \
  -H "Authorization: Bearer YOUR_ORDERS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "eventId": "signup_42",
    "installId": "INSTALL_ID",
    "eventType": "custom",
    "consent": true,
    "properties": { "eventName": "CompleteRegistration" }
  }'
```

SideShift counts an event once per `eventId`. If the app and your server both send one, give both the same ID
(`SideShift.track(_:eventId:)`).

## How a creator gets credit

Every method is exact:

| How the person came | What the SDK uses | Needs |
|---|---|---|
| Tapped **Get the app**, installed, opened | The link the page copied | Nothing; iOS may ask to allow the paste |
| Tapped the Paste button in your onboarding | The link the page copied | `SideShiftPasteButton` |
| Already had the app and tapped **I already have it** | Your universal link | Universal links and `handle` |
| Gave their email in a SideChat DM or on the link page | Hashed email | `identify(email:)` |
| A creator's SideChat DM went to their Instagram account | Hashed username | `identify(instagram:)` |
| Typed a creator code | The code | `applyCode` |

- A sale is credited to the last creator link the install came from in the 7 days before it.
- An App Store subscription keeps the creator it was first credited to for every renewal, unless the person comes through
  another creator's link in the 7 days before a renewal.
- Commissions are paid only on verified revenue: App Store purchases Apple signed, or orders from your server.

With App Store Connect connected in SideShift, the app's page also shows Apple's own download count per creator link, next
to the installs SideShift matched.

## Privacy

- **No advertising identifier, no fingerprinting.** The SDK never reads the IDFA or device details to identify a device.
- **Install ID.** A random ID per install, stored in the app's own storage, never shared with other apps.
- **Hashed identity.** `identify` sends SHA-256 hashes of the email (trimmed, lower case), phone (digits with country
  code) and Instagram username (lower case, no @). Matching them with what a person gave a creator links your app's data
  with SideShift's for measurement, which Apple's App Tracking Transparency rules treat as tracking. So by default the SDK
  sends them only after the person allows tracking (`ATTrackingManager.requestTrackingAuthorization`; the SDK never shows
  the prompt). You can turn this off with `SideShift.Options(identityNeedsTrackingPermission: false)` if your own privacy
  review concludes otherwise.
- **Consent.** Call `SideShift.setConsent(false)` when a person opts out: the SDK drops its queued events, stops sending,
  and tells SideShift to stop using that install.
- **Privacy manifest.** The package ships `PrivacyInfo.xcprivacy`. In App Store Connect, declare Purchases and Product
  Interaction (analytics, not linked), and, if you call `identify`, Email Address, Phone Number and Other Contact Info
  (third-party advertising, linked, used for tracking).

## Test your setup

1. Run your app on a phone. The app's **Setup** tab in SideShift shows the install within a minute.
2. Create a creator link for the app in SideShift, open it on the phone, tap **Get the app**, delete and reinstall your
   app from Xcode, and open it. The Setup tab shows a matched install.
3. Make a sandbox purchase. It appears as a test purchase.

Set the SDK's endpoint only if SideShift gives you another one: `SideShift.configure(appKey:endpoint:)`.

## API reference

| Call | What it does |
|---|---|
| `SideShift.configure(appKey:endpoint:options:)` | Starts the SDK. Call once at launch. |
| `SideShift.handle(_ url:)` | Credits a SideShift link the app opened. Returns `true` for a SideShift link. |
| `SideShift.identify(email:phone:instagram:)` | Hashes and sends who the person is, for matching. |
| `SideShift.track(_ result:)` | Sends an App Store purchase right after `purchase()`. |
| `SideShift.track(_ name:value:currency:eventId:)` | Sends a custom event. |
| `SideShift.trackPurchase(orderId:value:currency:productId:quantity:)` | Reports a non-App Store purchase. Shown, but commission comes from your server's order. |
| `SideShift.applyCode(_:)` | Credits a creator code. |
| `SideShiftPasteButton` | Apple's Paste button, reading a copied SideShift link with no prompt (iOS 16+). |
| `SideShift.setConsent(_:)` | Stops or resumes sending. |
| `SideShift.installId` | This install's ID, for your server's requests. |
| `SideShift.flush()` | Sends queued events now. |

### Options

| Option | Default | Meaning |
|---|---|---|
| `readsPasteboardOnInstall` | `true` | Read a copied SideShift link on the first open. |
| `openInterval` | 30 minutes | At most one `app_open` per interval. |
| `sendsPurchases` | `true` | Send App Store purchases, renewals and refunds. |
| `identityNeedsTrackingPermission` | `true` | Send `identify` only after the person allows tracking. |

## Support

Questions about your account: [SideShift Contact](https://sideshift.app/contact). Security issues: see
[SECURITY.md](.github/SECURITY.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
