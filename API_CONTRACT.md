# ThreadHive Widget API — resolved contract for the mobile SDKs

This is the **verified** contract the iOS + Android SDKs implement. It is checked
directly against the ThreadHive backend's public widget routes (config, ask,
confirm, identify, track, poll, conversations list/reply, attachments, typing,
csat, seen) and mirrors the behavior of the web chat widget — field names match
the server DTOs 1:1.

## Base URL & auth

- The host passes an **API base URL**, e.g. `https://app.example.com/api`.
- All widget endpoints live under **`{apiBaseURL}/v1/widget/...`**.
- Auth is **capability-based** — there is no token/cookie. The capability is the
  combination of values already in the URL/body:
  - `widgetKey` (public, safe to ship in a binary) identifies the workspace.
  - `visitor_id` (anonymous UUID the SDK mints + persists) scopes a visitor's
    conversations. Polling/reply/attachment/csat endpoints additionally **403** if
    a supplied `visitor_id` doesn't match the conversation's stored one.
  - `conversation_id` + `confirm_token` are per-thread / per-action capabilities.
- CORS is wide open on `/v1/widget/*` (designed to be called from any origin), so
  native clients have no preflight concerns.
- Errors are JSON `{"detail": "<code>"}` with a matching HTTP status. The SDK maps
  these to a typed `APIError`.

## Identity (`visitor_id`)

- A UUID minted on first run and **persisted in the secure store** (Keychain on
  iOS / EncryptedSharedPreferences on Android), **keyed per widget key**. The web
  client uses `__threadhive_vid_{widgetKey}` in localStorage — the SDK mirrors that
  per-key scoping.
- Constraints enforced by the backend: **8–64 chars**. A UUID (36 chars) satisfies this.
- `logout()` clears the stored `visitor_id` (and identity) and mints a fresh one.

---

## Endpoints

### 1. `GET /v1/widget/{widgetKey}/config.json`
Theming + state. No body. Cache briefly (server sends `Cache-Control: max-age=15`).

Response `WidgetPublicConfig`:
```jsonc
{
  "workspace_name": "Acme",
  "workspace_subdomain": "acme",
  "widget_key": "wk_…",
  "config": { /* opaque WidgetConfig blob: brand color, launcher, welcome, bot name, tabs… */ },
  "published_version": "v12" ,           // nullable
  "published_at": "2026-01-02T…Z",       // nullable
  "ai_available": true,                  // an LLM provider is configured → show "AI active"
  "availability": { /* business-hours schedule, opaque */ },  // nullable = always open
  "is_open": true,                       // server snapshot of open/closed
  "team": [{ "name": "Mia", "initials": "M", "color": "from-orange-400 to-pink-500", "avatar_url": null }],
  "team_overflow": 3,                    // "+N" more not shown
  "reply_time_label": "under 2 minutes"  // nullable
}
```
Special bodies:
- Domain-blocked origin → `{ "blocked": true, "detail": "domain_not_allowed" }` (200, `no-store`). **Not relevant to native** (no Origin header), but decode defensively.
- Unknown key → `404 { "detail": "widget_not_found" }`.

> `config` is stored opaquely by the backend. The SDK decodes it as raw JSON and
> reads known keys for theming (brand color, bot name, launcher). See the frontend
> `WidgetConfig` type for the full shape when wiring the UI.

### 2. `POST /v1/widget/{widgetKey}/ask`
Send a visitor message, get the bot reply. Rate-limited per key + per IP.

Request `AskRequest`:
```jsonc
{ "question": "string (≤2000, may be empty IF attachment_ids present)",
  "visitor_id": "uuid (8–64) | null",
  "attachment_ids": ["…"] | null }
```
Response `AskOut`:
```jsonc
{
  "answer": "string",                    // empty → render nothing (attachment-only / human-owned)
  "sources": [{ "source_id": "s", "source_name": "Docs / Billing", "score": 0.92, "chunk_url": "https://…|null" }],
  "used_rag": true,
  "conversation_id": "uuid | null",      // STORE IT → poll for later agent/bot msgs
  "handoff": false,                      // true → render answer as a system notice + start polling
  "pending_actions": [{ "run_id": "uuid", "name": "cancel_sub", "label": "Cancel subscription", "confirm_token": "…" }],
  "products": [{ "id": "uuid", "title": "Blue Widget", "price": "29.99", "currency": "USD",
                 "image_url": "https://…|null", "url": "https://…|null", "in_stock": true,
                 "source": "shopify|null", "add_to_cart_id": "v1|null" }]
}
```
Notes:
- `handoff: true` also occurs when the bot *deliberately* escalated — `answer` still
  carries a graceful line; render as a **system** bubble and keep polling.
- Retry with exponential backoff on transient failure (network / 5xx / 429-with-`Retry-After`).

### 3. `POST /v1/widget/{widgetKey}/actions/{runId}/confirm`
Confirm/decline a bot-prepared write action.

Request: `{ "confirm_token": "… (8–128)", "confirm": true }`
Response `ConfirmActionOut`: `{ "status": "ok|rejected|error|not_found|already_done", "message": "string" }`
→ Clear the prompt, show `message` as a bot bubble.

### 4. `GET /v1/widget/{widgetKey}/conversations/{conversationId}/poll`
Live polling for agent/bot/system replies + typing. Query: `since` (ISO cursor from
the previous poll, optional), `visitor_id` (optional but recommended → 403 guard).

Response `WidgetConversationPollOut`:
```jsonc
{
  "conversation_id": "uuid",
  "status": "open|snoozed|closed",
  "messages": [{
    "id": "uuid",
    "author_kind": "visitor|bot|agent|system",
    "author_name": "Mia" ,                // "You"/"ThreadHive"/"System" for non-agent kinds
    "author_avatar_url": "https://…|null",
    "body": "string",
    "sources": [ { … } ] | null,
    "created_at": "ISO",
    "attachments": [{ "id": "uuid", "name": "shot.png", "mime_type": "image/png", "size_bytes": 1234, "url": "/api/v1/widget/…?visitor_id=…" }],
    "delivered_at": "ISO|null",           // present on outbound msgs
    "read_at": "ISO|null"
  }],
  "cursor": "ISO | null",                 // echo back as `since` next poll
  "typing": { "visitor": false, "agent": true },
  "assigned_agent": { "name": "Mia", "initials": "M", "color": "…", "avatar_url": "…|null" } | null,
  "csat_score": 5 | null                  // already-rated → don't re-prompt
}
```
- Poll every **3–5s** while the chat is open; **stop when backgrounded**.
- Reconcile by `id` (dedupe); advance `since` to `cursor`.
- Attachment `url` is **relative + API-prefixed** (`/api/v1/widget/…`). The SDK
  resolves it against the **origin of `apiBaseURL`** (strip the `/api` path; the URL
  already includes `/api/...`). It embeds `visitor_id` as a query param.

### 5. `GET /v1/widget/{widgetKey}/conversations?visitor_id=…&limit=20`
"Messages" tab — the visitor's past threads (newest first). `visitor_id` **required**.

Response: `{ "items": [WidgetConversationSummary] }`
```jsonc
{ "id": "uuid", "status": "open|snoozed|closed", "subject": "…",
  "last_message_preview": "…", "last_message_author": "visitor|bot|agent|system|null",
  "last_message_at": "ISO|null", "ai_handled": true, "unread": false }
```

### 6. `POST /v1/widget/{widgetKey}/conversations/{conversationId}/messages`
Visitor reply on an existing thread (vs. starting a new `/ask`). If the thread is
still bot-handled it runs RAG and replies; if an agent took over it just stores the message.

Request: `{ "body": "string (≤10000)", "visitor_id": "…", "attachment_ids": ["…"]? }`
Response: `{ "ok": true, "conversation_id": "uuid", "message_id": "uuid", "handoff": bool, "bot_reply": { "id": "uuid", "body": "…" } | null }`

> The bot reply also lands via `/poll`; the inline `bot_reply` is a convenience.
> Render new messages from `/poll` to keep one rendering path.

### 7. `POST /v1/widget/{widgetKey}/conversations/{conversationId}/attachments?visitor_id=…`
Multipart upload (`file` field). `visitor_id` **required** (query or
`x-threadhive-visitor-id` header). Allowed: png/jpg/jpeg/gif/webp/pdf, **≤10 MB**.

Response `MessageAttachmentOut`: `{ "id", "name", "mime_type", "size_bytes", "url" }`
→ pass `id` to `/ask` or `/messages` as `attachment_ids`.

`GET …/attachments/{attachmentId}?visitor_id=…` streams the bytes (used directly as image `src`).

### 8. `POST /v1/widget/{widgetKey}/conversations/{conversationId}/typing`
Body: `{ "visitor_id": "…", "is_typing": true }` → `{ "typing": { "agent": bool, "visitor": bool } }`.
Ping ~every 2s while composing; server TTL (~4s) auto-clears.

### 9. `POST /v1/widget/{widgetKey}/identify`
Link a logged-in user. `user_hash = HMAC-SHA256(identitySecret, user_id)` is computed
by the **host's backend** and forwarded — never compute it in the app.

Request `IdentifyIn`:
```jsonc
{ "visitor_id": "… (8–64, required)", "user_id": "… (1–120, required)",
  "email": "a@b.com|null", "name": "…|null", "phone": "…|null", "avatar_url": "…|null",
  "role": "…|null", "company": "…|null", "plan": "…|null", "mrr": 0.0,
  "created_at": "ISO|null", "traits": { … }|null, "user_hash": "…|null" }
```
Response: `{ "ok": true, "contact_id": "uuid", "verified": bool }` (`verified=false` if hash missing/mismatched — still linked, just flagged).

### 10. `POST /v1/widget/{widgetKey}/track` (optional)
Request `TrackIn`: `{ "visitor_id": "… (8–64)", "type": "pageview|custom", "name"?, "url"?, "referrer"?, "properties"?, "tz"?, "utm_source"?, "utm_medium"?, "utm_campaign"? }`
Response: `{ "ok": true, "contact_id": "uuid" }`

### 11. `POST /v1/widget/{widgetKey}/csat` (optional, parity)
Request: `{ "conversation_id": "… (required)", "visitor_id"?, "score": 1..5, "comment"? }`
Response: `{ "ok": true, "submission_id": "…", "conversation_id": "uuid" }`

### 12. `POST /v1/widget/{widgetKey}/nps` (optional)
Request: `{ "visitor_id"?, "score": 0..10, "comment"? }` → `{ "ok": true, "submission_id", "contact_id" }`

### 13. `POST /v1/widget/messages/{messageId}/seen` (optional — read receipts)
Note the path: **under `/v1/widget/`, not under a conversation**.
`visitor_id` via body `{ "visitor_id": "…" }` **or** header `x-threadhive-visitor-id`.
Response: `{ "ok": true, "read_at": "ISO" }` (or `{ "ok": true, "skipped": "not_outbound" }`).

---

## Phase-2 dependency (push)

There is **no native device-token registration endpoint yet** — the backend has web
push only (VAPID/`PushSubscription`). Registering APNs/FCM tokens for new-agent-reply
notifications requires a small **new backend endpoint** (associate a device token with
the visitor/contact). Flagged as a dependency; the SDK exposes a `registerPushToken`
hook behind the `WidgetAPI` interface so it's a drop-in once the route ships.

## Mobile-specific behavior differences (document for users)

- **Add-to-cart**: the web widget adds to the cart in the host page's session. A
  native app has no merchant web page, so **mobile "Add" opens the product/checkout
  `url`** in an in-app browser (SFSafariViewController / Chrome Custom Tabs). If
  `url` is null, "Add" is disabled.
- **Polling, not SSE/WS**: matches the web widget. 3–5s while open, stop when backgrounded.
- **Attachment URLs** are relative + `/api`-prefixed; resolve against `apiBaseURL`'s origin.
