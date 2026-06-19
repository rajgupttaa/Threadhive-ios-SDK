# ThreadHive iOS — Demo app

A minimal SwiftUI app that exercises the SDK end-to-end: configure, anonymous
chat, identify, present chat, product cards, agent-reply polling, and the unread
badge.

`DemoApp.swift` is provided as source (rather than a checked-in `.xcodeproj`, which
doesn't merge well). Wire it into an app target in ~2 minutes:

1. **Create an app target** — Xcode ▸ File ▸ New ▸ Project ▸ iOS ▸ App
   (Interface: SwiftUI, Life Cycle: SwiftUI App). Delete the generated
   `ContentView.swift` and the `…App.swift` file.
2. **Add the SDK** — File ▸ Add Package Dependencies… ▸ choose **Add Local…** and
   pick `mobile-sdks/ios` (or use the published Git URL). Add the `ThreadHive`
   library to your app target.
3. **Drop in the demo** — drag `DemoApp.swift` into the target (it declares
   `@main`, so there must be no other `@main`).
4. **Set your keys** — edit `Demo.widgetKey` and `Demo.apiBaseURL` at the top of
   `DemoApp.swift`.
5. **Run** on a simulator or device.

## Try it

- **Open chat** → ask the bot a question (RAG answer + citations).
- Ask about a product → product cards render; **Add** opens the product URL in an
  in-app Safari sheet.
- Trigger a bot action (e.g. "cancel my subscription" if your workspace has a
  confirm-required action) → a **Confirm / Cancel** prompt appears.
- Reply from the **ThreadHive dashboard inbox** → the agent message appears in the
  app within a poll interval, and the unread badge updates.
- **Identify** links the visitor to `u_123` (pass a real `userHash` from your
  backend in production); **Log out** unlinks and resets the visitor.

## Notes

- Attachments require an existing conversation (send one message first) — this
  mirrors the web widget, which gates uploads on a conversation id.
- For verified identity, compute `userHash = HMAC-SHA256(identitySecret, userID)`
  on your server (see the SDK README).
