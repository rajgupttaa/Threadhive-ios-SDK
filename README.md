# ThreadHive iOS SDK

Native in-app messaging for the [ThreadHive](https://threadhive.io) support bot +
human agents — feature parity with the web chat widget, as a Swift package.

- AI Q&A (RAG) with citations, handoff-to-human, and live agent replies
- Product cards, bot "Actions" confirm prompts, attachments
- Anonymous + identified visitors (HMAC), unread badge, theming from your widget config
- Tiny surface, no third-party dependencies, iOS 15+, SwiftUI + UIKit hosts

> **Status:** Networking + the full SwiftUI chat experience are implemented
> (launcher, message list, composer, typing, citations, agent-reply polling,
> product cards, bot-action confirms, attachments, theming). Drive it with one
> line via `ThreadHive.presentChat(from:)`, embed `ThreadHiveChatView`, or build
> a custom UI on the public `WidgetAPI` client.

## Install

### Swift Package Manager (primary)

In Xcode: **File ▸ Add Package Dependencies…** and enter the repo URL, or add to `Package.swift`:

```swift
.package(url: "https://github.com/rajgupttaa/Threadhive-ios-SDK.git", from: "1.0.0")
```

then add `"ThreadHive"` to your target's dependencies.

### CocoaPods

```ruby
pod 'ThreadHive', '~> 1.0'
```

## 5-minute quickstart

```swift
import ThreadHive

// 1. Configure once at launch (e.g. in your AppDelegate / App init).
ThreadHive.configure(
    widgetKey: "wk_live_…",
    apiBaseURL: URL(string: "https://app.example.com/api")!   // your API origin + /api
)

// 2. (Optional) Link the signed-in user. See "Identity" below for userHash.
ThreadHive.identify(userID: "u_123", email: "ada@example.com", userHash: serverComputedHash)

// 3. Present the chat — one line from any UIViewController.
ThreadHive.presentChat(from: self)

// 4. Unread badge.
ThreadHive.unreadCount { count in /* update your tab badge */ }

// 5. Sign-out: unlink + reset to a fresh anonymous visitor.
ThreadHive.logout()
```

### SwiftUI

```swift
// Embed the whole experience, or drop in the floating launcher.
struct SupportTab: View {
    var body: some View {
        ThreadHiveChatView()          // built from the configured session
    }
}
// or, a FAB with an unread badge that presents the chat:
ThreadHiveLauncher()
```

The `widgetKey` is **public** and safe to ship in your binary — it only loads the
published widget config and posts visitor messages.

## Identity (HMAC) — do this on your server

To link a logged-in user verifiably, your **backend** computes
`userHash = HMAC-SHA256(identitySecret, userID)` and returns it to the app. The
identity secret never touches the device.

Node:

```js
import crypto from "node:crypto";
const userHash = crypto
  .createHmac("sha256", process.env.THREADHIVE_IDENTITY_SECRET)
  .update(userId)
  .digest("hex");
```

Python:

```python
import hmac, hashlib
user_hash = hmac.new(identity_secret.encode(), user_id.encode(), hashlib.sha256).hexdigest()
```

Pass the result into `ThreadHive.identify(userID:…, userHash:…)`. Without a valid
hash the user is still linked but flagged unverified server-side.

## Theming

Theming is derived from your published widget config (`config.json`): brand color,
bot name, team avatars, online/away state + reply-time label. Override selectively:

```swift
var config = ThreadHiveConfiguration(widgetKey: "wk_…", apiBaseURL: url)
config.theme = ThemeOverrides(brandColorHex: "#5b21b6", botName: "Ada", colorScheme: .system)
ThreadHive.configure(config)
```

## Security & networking knobs

```swift
var config = ThreadHiveConfiguration(widgetKey: "wk_…", apiBaseURL: url)
config.urlSession = myPinnedSession      // inject a cert-pinned URLSession
config.logger = ConsoleLogger(minimumLevel: .debug)
config.pollInterval = 4                   // seconds between agent-reply polls
config.retryPolicy = .default             // exp. backoff on /ask + /config
ThreadHive.configure(config)
```

- HTTPS only; no pinning by default (inject your own session to pin).
- `visitorID` is stored in the **Keychain** (`kSecAttrAccessibleAfterFirstUnlock`),
  scoped per widget key; cleared on `logout()`.

## Public API reference

| Symbol | Purpose |
| --- | --- |
| `ThreadHive.configure(widgetKey:apiBaseURL:)` / `configure(_:)` | One-time setup |
| `ThreadHive.presentChat(from:)` | Present the chat modally (UIKit) |
| `ThreadHive.chatViewController()` | A `UIViewController` to embed/present |
| `ThreadHiveChatView()` / `ThreadHiveLauncher()` | SwiftUI embed + floating launcher |
| `ThreadHive.identify(userID:email:name:userHash:traits:)` | Link a known user |
| `ThreadHive.logout()` | Unlink + reset visitor |
| `ThreadHive.visitorID` | Current anonymous/linked visitor id |
| `ThreadHive.unreadCount { }` / `unreadCount() async` | Unread badge |
| `ThreadHive.track(_:properties:)` | Custom analytics event |
| `ThreadHive.api` | The full `WidgetAPI` (ask, poll, confirm, attachments, …) |
| `ChatViewModel` | Observable engine for a fully custom SwiftUI chat |

`WidgetAPI` mirrors the backend 1:1 — see [`API_CONTRACT.md`](API_CONTRACT.md)
for every endpoint, request, and response.

## Commerce: "Add" on mobile

The web widget adds a product to the host page's cart session. A native app has no
merchant web page, so **"Add" opens the product/checkout `url` in an in-app browser**
(SFSafariViewController). If `Product.url` is nil, "Add" is unavailable.

## Push notifications (Phase 2)

New-agent-reply push requires a backend endpoint to register APNs device tokens
(the backend currently supports web push only). The SDK will forward tokens through
`WidgetAPI` once that route ships — tracked as a dependency.

## Tests

- Canonical suite (Xcode / CI): `swift test`
- No-Xcode smoke runner: `swift run ThreadHiveSmoke`

## License

See [LICENSE](LICENSE).
