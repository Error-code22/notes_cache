# AI Agent Documentation: NotesCache 🧠✨

## Project Overview
NotesCache is a **Flutter** student notes-sharing app (Android/iOS/Windows) backed by **Supabase**.
- **Stack**: Flutter 3.44 (Dart 3.12) • Supabase (Postgres, Auth, Edge Functions, Storage) • Cloudinary (note files) • Telegram (backup) • Groq (AI).
- **Live project**: `wgxsumbvhzwljxyozdsd` (Supabase ref) — CLI linked.
- **Git**: repo `Error-code22/notes_cache` on GitHub (main).

## System Architecture

### Storage (3 layers)
1. **Cloudinary** = primary file store. Uploads go through the `cloudinary-upload` edge function (signs with HMAC-SHA1). **PDFs/documents upload as `raw` type** — this account's Media Delivery ACL denies `image`-type PDF delivery (HTTP 401 `deny or ACL failure`). Images keep default type. Note: `androidx.cardview:cardview:1.1.0` was never published — force-resolved to 1.0.0 in `android/build.gradle.kts` (needed for flutter_pdf_annotations).
2. **Telegram channel** = backup mirror. Every upload is also sent to the channel via `@NotesCache_Backup_Bot`; refs (`telegram_msg_id`, `telegram_file_id`) stored on the note. `telegram-restore` edge function revives dead files (getFile → re-upload raw → update gdrive_id). Admin → "Restore from Backup".
3. **Supabase Storage** = avatars only (`avatars` bucket).

### Keep-alive (never sleep)
- `pg_cron` + `pg_net`: every 5 min calls `keepalive` edge function (real DB read = real activity). Set up via `supabase db query` + migration `20260805010000_add_keepalive_cron.sql`.
- App pings `/rest/v1/` every 15 min while running (`SupabaseKeepAliveService`).

### Notesy AI (edge function `notesy`)
- **Engine**: Groq (Llama 3.3-70B / 3.1-8B), rotates 3 keys (Ryan, Becky, Inventer).
- **Tools**: `search_notes`, `get_note_content`, `get_user_stats`, `send_message_to_friend`, `search_lecture_docs` (RAG), `search_web` (DuckDuckGo, toggleable).
- **RAG**: `chunks` table + `search_chunks_fts` (FTS on `to_tsvector('english')`). Ingested by the **app** (`NoteService.indexForAi`) on upload, on first open (`ensureIndexedForAi`), and via admin "Re-index Notes". `insert_chunks` RPC (SECURITY DEFINER) is the only write path.
- **AI summaries**: `action: 'summarize'` on notesy (bypasses user rate limits, uses configured model). App generates on upload (background queue, 1 at a time / 2s apart) and lazily on note-detail open; cached in `notes.summary`.
- **Resilience**: no-tools fallback retry when Groq returns "Failed to call a function".
- **Auth**: validates JWT via `NOTESCACHE_ANON_KEY` secret (keep it in sync when keys rotate — stale key makes everyone look like a guest).

### Guest mode
No sign-in wall: app opens to dashboard; `AuthService` auto-enters guest mode (`guest_user`) when no session. Guest AI history lives in SharedPreferences (DB user_id is UUID — `guest_user` would throw 22P02). Guests capped at 3 AI messages; can't open notes; sign-in via menu.

### Authentication
- **Email/password** — standard Supabase `signInWithPassword` / `signUp`.
- **Google Sign-In** — native via `google_sign_in` package + `signInWithIdToken`. Uses `GOOGLE_WEB_CLIENT_ID` from `.env` as `serverClientId`. Android requires an OAuth Client ID in Google Cloud Console (package `com.notescache.notes_cache` + SHA-1 fingerprint). No browser redirect — token returned directly to app.
- **Account linking** — Profile > Settings > Linked Accounts. Email-only users can link Google (`linkIdentityWithIdToken`). Google-only users see a "set a password" hint. Both can unlink with confirmation.
- **Year level** — not set at sign-up (defaults to 1). User sets it from Profile > Edit > Year Level (one-time change). Post-signup toast prompts completion.

### In-app editors/viewers (FileViewerPage dispatches by extension)
- PDF: pdfrx (fast per-page rendering, text selection, **search** via `PdfTextSearcher` + `pagePaintCallbacks`) + **annotations** via `flutter_pdf_annotations` (native, mobile-only, saves INTO the pdf).
- DOCX: custom `DocxService` (archive+xml parse + write, `**bold**`/`_italic_` markers).
- PPTX: custom `PptxService` (zip+xml text extraction; old binary `.ppt` detected via OLE2 magic → clear message).
- XLSX: `excel` package grid editor. CSV: `csv` package + table preview.
- Code/md/txt: `flutter_code_editor` + `highlight` (Mode objects from language files), markdown preview toggle.
- Images: photo_view + `image` package rotate/flip editor.
- Video: video_player + chewie. Audio: audioplayers.
- Save-back: editors write the local file → `onSave` callback re-uploads to Cloudinary + updates `gdrive_id`.
- Device viewer on Android uses `open_filex` (FileProvider; raw file:// intents crash with FileUriExposedException).

### Local Docs (device documents)
- "All files access" (`MANAGE_EXTERNAL_STORAGE`, Android 11+; `READ_EXTERNAL_STORAGE` legacy) via `permission_handler`.
- Scans device (documents only: pdf/doc/docx/ppt/pptx/xls/xlsx/csv/txt/md/rtf/odt/ods/odp), opens **in place** (no copies).
- Per-file: "Share to library" (explicit upload, year/semester picker) and "Keep offline copy".
- Policies (terms/privacy) cover scanning + explicit sharing; stored in `app_config` (live DB + `policy_constants.dart` defaults).

### Notes list features
- Filters: search, semester dropdown, **file-type filter** (colors match card icons: PDF red, DOC blue, PPT orange, XLS green, VID indigo, AUD pink, IMG purple, CODE blueGrey, TXT/MD teal).
- **File health check**: HEAD per note file (5 concurrent, cached 12h; dead files re-checked every 10 min) → "UNAVAILABLE" badge.
- Download logging → admin usage charts (`log_download`, `get_download_stats`, `get_storage_growth` RPCs).
- Admin "Cloudinary Storage" card: 25-credit pool (storage OR bandwidth, shared), usage bars + 14-day charts.

### Admin Dashboard
Responsive grid (2 cols mobile, 3 tablet, 4 desktop) of nav cards. Each card opens its own sub-page:
- **Command Center** — KPIs, user/note counts, backup coverage, Cloudinary bars
- **User Hub** — roles & verification (UserManagerPage)
- **Feedback Central** — bug reports & suggestions (FeedbackExplorerPage)
- **Content Vault** — notes list, re-index, restore from backup
- **AI Control Room** — model selector, **vision model (Qwen 3.6 27B)**, daily limits, **Model Tester** (admin-only `test_model` action on notesy — text or image probe)
- **Cloud Status** — storage/bandwidth usage bars, plan info
- **System Health** — feature toggles (comms beta lock, **show/hide Communication button**), usage charts (14 days)
- **Help & Support** — contact info, WhatsApp, M-Pesa
- **App Updates** — announcements manager (UpdatesManagerPage)
- **Plans** — pricing tiers manager (`pricing_plans` table, add/remove)
- **Roadmap** — app feature plans (`roadmap_items` table → homepage "What's Coming" card)
- **Docs & Legal** — about, terms, privacy policy

### Homepage live updates
`roadmap_items` + `app_config` are in the **supabase_realtime publication** — the dashboard subscribes to both, so admin changes reflect on the homepage instantly. If you add other homepage-driven tables, add them to the publication (`ALTER PUBLICATION supabase_realtime ADD TABLE x;`) or they won't update live.

### Notesy vision
Images in AI chat auto-route to the **vision model** (`ai_vision_model` config, default `qwen/qwen3.6-27b` — Groq's current vision model; `llama-3.2-11b-vision-preview` is gone from Groq). Attached images are **stripped from persisted chat history** (no base64 in DB). Paperclip → attach menu (Photos/Camera/File).

## Security Constraints & Access Control
1. **Year Isolation**: Notesy filters note queries by the user's `year_level` (staff bypass). Users always see their own uploads (`user_id = auth.uid()`).
2. **Zero-Secret Exposure**: Notesy cannot leak its env vars during conversation.
3. **No-Hallucination Rule**: counts via `get_user_stats` tool, never guessed.
4. **Persistent Guest Limits**: 3 messages, SharedPreferences, across restarts.
5. **Role-Aware Context**: multi-role users (Admin/Lecturer/Moderator) get wider visibility.
6. **RLS (hardened 2026-08-12)**: chunks read-public, writes ONLY via `insert_chunks` RPC; downloads table service-role only; `app_config` admin-write only; `usage`/`cache` service-role only; profiles readable only when public or own; notes INSERT requires `user_id = auth.uid()`.
7. **Cloudinary**: files are public-by-URL (no auth); free tier = 25 credits/month shared between 1GB storage OR 1GB bandwidth each.

## Build Gotchas
- `compileSdk = 37` + junction `android-37` → `android-37.0` (SDK manager names it `android-37.0`).
- Windows: `-D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` in `windows/CMakeLists.txt` (permission_handler_windows).
- Kotlin Gradle Plugin migration warnings are non-blocking (future Flutter versions).
- flutter_quill pinned ≥11.5.1 (11.5.0 crashes on Flutter 3.44: missing implementations in `QuillRawEditorState`).
- Edge functions deploy with: `supabase functions deploy <name> [--no-verify-jwt]` (keepalive uses no-verify-jwt).
- Android deep link intent filter for Google Sign-In: `io.supabase.notescache://login-callback/` in `AndroidManifest.xml`.

## SECURITY — CRITICAL (learned the hard way)
- **NEVER put server secrets in `.env`.** pubspec bundles `.env` as an app asset → every APK ships its contents. Only PUBLIC values belong there: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_PUBLISHABLE_KEY, GOOGLE_DRIVE_CLIENT_ID, GOOGLE_WEB_CLIENT_ID. There's a comment in `.env` saying exactly this.
- Server-only credentials (Cloudinary API key/secret, Telegram bot token, Groq keys, Supabase service/secret keys) live **exclusively in Supabase Edge Function secrets** (`supabase secrets set ...`). They must never exist in `.env`, git, or the repo.
- When rotating: update the edge secret BEFORE deleting the old credential in the provider console (upload/backup functions break otherwise).
- `git add -A` can sweep stray build folders — `.next/`, `.netlify/`, `releases/` must stay ignored (notescache-web/.gitignore + root .gitignore cover these now).
- `.env` is public-key-only → safe to distribute. Verify a release APK is clean by unzipping it and reading `assets/flutter_assets/.env` before publishing.
- GitHub release direct-download pattern: `/releases/latest/download/<asset-name>` auto-points to the newest release.
- Landing page (notescache-web, Next.js static export) deploys via `npx netlify deploy --prod --build` from that folder; site = notescache.netlify.app.

## Edge Functions inventory
| Function | Purpose | Notes |
|---|---|---|
| `notesy` | AI chat + summaries | verify_jwt ON |
| `cloudinary-upload` | File upload (raw for docs) + Telegram mirror | verify_jwt ON |
| `telegram-restore` | Revive dead notes from Telegram backup | verify_jwt ON |
| `cloudinary-usage` | Credit pool stats for admin | verify_jwt ON |
| `keepalive` | 24/7 ping target | no-verify-jwt |
