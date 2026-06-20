# Changelog

All notable changes to the ThreadHive iOS SDK are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/) and the project follows
[Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-06-20

### Added — Native push notifications
- `ThreadHive.registerPushToken(_:environment:)` / `unregisterPushToken()` — register the
  APNs device token so backgrounded/closed apps receive agent replies. Auto-unregistered
  on `logout()`; re-call after `identify` / a fresh login.
- `ThreadHive.handleNotification(userInfo:)` + `conversationID(fromNotification:)` —
  deep-link a notification tap to the conversation in the payload.
- `WidgetAPI.registerDevice` / `unregisterDevice` (`POST`/`DELETE /v1/widget/{key}/devices`),
  with `DeviceRegisterRequest` / `DeviceUnregisterRequest` / `DeviceResponse` and an
  `APNSEnvironment` enum (`.automatic` → sandbox on Debug builds).

Requires each workspace to add its APNs key on Dashboard → Settings → Mobile Push.

## [1.0.0]

### Added — Milestone 1: networking + models + persistence
- Typed models for every backend DTO: `WidgetPublicConfig`, `AskRequest`/`AskResponse`
  (with `AskSource`, `PendingAction`, `Product`), `ConfirmActionRequest`/`Response`,
  `ConversationPoll`, `WidgetMessage`, `MessageAttachment`, `TypingState`,
  `ConversationSummary`, `SendMessageResponse`, `IdentifyRequest`/`Response`,
  `TrackRequest`/`Response`, `CSATRequest`/`Response`, `SeenResponse`, and a
  type-erased `JSONValue` for opaque config/traits blobs.
- `WidgetAPI` protocol + `WidgetAPIClient` (URLSession, async/await): config, ask,
  confirm, poll, conversations list, reply, attachment upload (multipart), typing,
  identify, track, CSAT, read receipts. Exponential-backoff retry on `/ask` and
  `/config.json`; typed `APIError` mapping (404/403/429/blocked/transport/decoding).
- `WidgetEndpoints` URL builder + relative-attachment-URL resolution.
- Keychain-backed `visitor_id` persistence (`SecureStore` abstraction with Keychain
  + in-memory implementations), per-widget-key scoping, reset on logout.
- TTL config cache and local unread tracking for the badge.
- Public `ThreadHive` facade: `configure`, `identify`, `logout`, `visitorID`,
  `unreadCount`, `track`, `api`.
- XCTest suite (decoding, endpoints, storage, client retry/error-mapping, session)
  plus a no-Xcode `ThreadHiveSmoke` runner.

### Added — Milestones 2–5: chat UI
- `ChatViewModel` (`@MainActor` `ObservableObject`): ask/reply send flow, optimistic
  bubbles with server-id reconciliation (no duplicate echoes), agent-reply polling
  with typing + assigned-agent swap, bot-action confirm flow, product opens, CSAT,
  and attachment staging. Fully unit-tested.
- SwiftUI UI: `ThreadHiveChatView` (header + message list + composer), brand-gradient
  header with team faces / online + reply-time, message bubbles, citation chips,
  product cards, Confirm/Cancel prompts, typing indicator, attachment chips,
  `ThreadHiveLauncher` (FAB with unread badge), and `ResolvedConfig`/`ThreadHiveTheme`
  theming from the published widget config + host overrides (light/dark).
- UIKit interop: `ThreadHive.presentChat(from:)`, `ThreadHive.chatViewController()`,
  in-app browser (`SFSafariViewController`) for product/citation links, and a
  document/photo attachment picker.
- Conversation-resume persistence (reopen the same thread, like the web widget).
- Demo app (`Examples/ThreadHiveDemo`) + view-model smoke coverage.

### Pending
- "Messages" history tab (list/reopen past threads) — list endpoint is wired in the
  client; the tab UI is the remaining piece.
- Phase 2: native push-token registration (blocked on a backend endpoint).
