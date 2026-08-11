# Project Progress Log 🚀📈

## Latest Milestone: v1.0.2 + UX & Admin Fixes (2026-08-11)

### v1.0.2 shipped (APKs + Windows)
- **In-app updater** — checks GitHub releases on open; "Update available (vX — you have vY)" dialog → download → system installer. Uses `package_info_plus` + `open_filex` (already in deps). `REQUEST_INSTALL_PACKAGES` in manifest. Android-only.
- **Guests blocked from library uploads** — FAB hidden (only lecturers/admins see it); the upload page shows a "Sign in to upload" gate pointing to Donate as the anonymous channel.
- **Theme toggle fixed** — from system mode, first click now goes to light (visible change) rather than dark (invisible no-op). Plus `_userCustomized` flag prevents profile-sync from clobbering manual changes.
- **Donate card wording** — "Share notes with everyone on the app" (was confusingly similar to Academic Notes).
- **Demo-mode yellow banner** on dashboard for guests: "Demo mode: browsing & donating only. Sign in for full access."
- **Admin Updates Manager** — Push Update now opens a full manager page: list all announcements, add new, delete junk. Replaces the old dialog-only flow.
- **Desktop Local Docs** — folder picker (FilePicker.getDirectoryPath) replaces the phone-style scan on Windows; document lists use lazy `ListView.builder` (1,850+ docs scroll smoothly).
- **Landing page** — clearer APK labels (64-bit "most phones" vs 32-bit), Chrome download stall tip, Windows button.

### Critical fixes (already live)
- **Offline startup** — profile DB fetch had no timeout (30s+ hang on slow/no network). Now 5s timeout → offline cache → guest fallback if no cache. Dashboard loads in seconds offline.
- **Feedback Explorer** — was returning empty because the `profiles(full_name)` embed 400'd under RLS. Now uses `list_feedback()` SECURITY DEFINER RPC (bulletproof, always works). Migration `20260810010000_list_feedback.sql`.
- **Guest feedback + donations** — `app_feedback`/`donated_notes` insert policies were `authenticated`-only; added `anon` policies (guest inserts with `user_id IS NULL`). Migration `20260810000000_guest_inserts.sql`.
- **Registration wall removed** — email confirmation disabled (`mailer_autoconfirm: true` via management API); signups are instant now (was the launch blocker — 0 signups out of 40+ downloads).

### Stats (2026-08-10)
- Total downloads: **34** (v1.0.0 + v1.0.1 combined). Windows: 3 downloads on first day.
- 1 star. 8 users total (pre-launch), 0 new signups at time (email wall was still up — now fixed).
- Real feedback already coming in: "I have notes from 1st year, so I dunno what note is for which", "demo student can upload notes", "when i upload a bug i get weird symbols" (the mojibake, now fixed).

## Previous Milestone: Public Launch & Secret-Leak Cleanup (2026-08-07)

## Previous Milestone: Public Launch & Secret-Leak Cleanup (2026-08-07)

### 1. The Leak (what happened)
- Repo made **public** → GitHub/Supabase/Google scanners found secrets inside the **committed APKs** (`releases/` folder, old commit).
- **Root cause:** pubspec bundles `.env` as an asset → **every APK ever built contained the whole old `.env`** — including SUPABASE_SECRET_KEY, Cloudinary API secret, Telegram bot token, Groq/Gemini keys, Drive client secret, and (in older builds) the GCP `service_account.json`.
- Fallout: Supabase **revoked** the sb_secret key; Google **disabled** the GCP service-account key.

### 2. The Cleanup (all done)
- **`.env` stripped to public-only values** (URL, anon key, publishable key, Drive client ID). Server-only secrets now live ONLY in Supabase Edge Function secrets. Comment added to `.env` warning never to add secrets there.
- **Git history purged** — `releases/` removed from all commits (filter-branch + force-push).
- **APKs rebuilt with the clean `.env`** and verified secret-free (extracted the bundled `.env` from the APK and checked every secret string — all gone). Release assets replaced (same names → links unchanged).
- **Keys rotated:** Groq (user), Cloudinary (new key `814129955457977` — verified working in edge functions), Telegram (new token, verified end-to-end: backup mirror posted message 204), Supabase secret (regenerated, stored in password manager only), GCP service key (disabled by Google; delete console entry at leisure), Gemini (ignored — unused).
- supabase CLI **reinstalled** (npm global, v2.113.0 — old binary vanished from PATH; `supabase login` redone by user).

### 3. notescache-web (landing/download site)
- **Full Next.js web-app source was lost** during the leak cleanup (interrupted `git checkout` synced the folder to a commit that lacked the source; the stash holding it was pruned by `git gc`). Compiled `.next` output survived but the TSX/configs didn't.
- **Rebuilt as a minimal Next.js 16 static landing page** (download hub): hero, APK download buttons (arm64/v7a, auto-updating `/releases/latest/download/...` URLs), GitHub link, WhatsApp group + support. "Web version coming soon" note.
- **Deployed to Netlify** (static export, `output: 'export'`): **https://notescache.netlify.app** (renamed from the random slug). Deploy command: `cd notescache-web && npx netlify deploy --prod --build`.
- Gitignores added: `.next/`, `.netlify/`, `.env*.local` (node_modules was already covered by root gitignore).

### 4. Distribution chain (final)
- **GitHub release** = canonical downloads: `github.com/Error-code22/notes_cache/releases/tag/v1.0.0` (3 APKs, clean).
- **Direct APK link** (what goes in WhatsApp groups): `github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-arm64-v8a.apk` — auto-points to newest release.
- **Landing page** = notescache.netlify.app (links to both).
- Zero downloads of the leaky APKs were ever recorded (repo was private; release created after cleanup).

### 5. Lessons (codified in AGENTS.md)
- Never put server secrets in `.env` — it's bundled into the APK as an asset. Only public values (Supabase URL/anon/publishable) belong there.
- Edge function secrets are the ONLY home for server credentials.
- Check `git add -A` output for stray build folders (`.next`, `.netlify`) before committing.

## Previous Milestone: Bug Hunt Round + First Release Build (2026-08-06)

### Bug fixes (this round)
- **docx blank editor — root cause found**: XML parser matched elements with `namespace: 'w'` (a *prefix*) but package:xml matches by namespace URI — every document silently parsed as empty. Fixed; verified with real library file (361 paragraphs extracted). New `tool/test_docs.dart` for parser regression tests.
- **pptx spinner**: parser verified working (8 slides from real file, lazy decompression via `decodeBuffer(InputStream)`); the spin was the legacy Google Drive download (bare ID + 12MB via Drive redirects). All file downloads now have a 60s timeout with friendly errors.
- **Scan misses WhatsApp docs**: docs live in `Android/media/...` which the scan skipped (over-aggressive `Android/` skip) + depth limit too shallow. Now scans `Android/media`, skips only `Android/data`+`Android/obb` (truly blocked), depth 8. Verified via adb: 3 PDFs found on the A207F.
- **Search keyboard** now dismisses on scroll/tap (PDF viewer + notes list).
- **Dashboard**: Workspace Hub header removed; separate "Report Bug / Suggest Feature" card under Notesy Memory Lab (→ FeedbackPage); dead "Storage Explorer" admin tile removed.
- **Android 10 permission path** added for legacy devices (kept for safety; minSdk is now 30 anyway).
- `android:allowBackup="false"` (blocks adb backup extraction); `fullBackupContent="false"`.

### Offline-first
- Notes list was cached offline, **files weren't**. Added: "Download All for Offline" (5 concurrent, persisted to app dir), green **OFFLINE** badge when a file exists locally, friendly offline error instead of raw SocketException.
- Offline model: first run needs internet once; then full offline reading/editing/annotating.

### Release build
- `minSdk = 30` (Android 11+ only) — simplifies permissions.
- `flutter build apk --release --split-per-abi` → arm64 (41.6MB) / armeabi-v7a (38MB) / x86_64 (44.1MB). AOT = no more debug jank.

### Quota answers (for the record)
- Supabase free: edge functions 500K calls/mo ≈ 5-8K users; DB 500MB (chat archiving buys headroom); egress tiny (files served by Cloudinary). Cloudinary 25-credit pool is the first real ceiling (~a few hundred active students with downloads).

## Previous Milestone: Legacy Office → PDF Migration (2026-08-06)

### Legacy .ppt/.doc files converted (12 files)
- Problem: 12 notes (11 old binary `.ppt` + 1 `.doc`) unreadable in-app. Cloudinary conversion tested and **cannot convert** (raw assets pass through `f_pdf` unchanged; image/document types reject the bytes).
- Solution: **one-time local conversion** using the installed Microsoft Office 2019 (PowerPoint COM SaveAs PDF=32, Word COM SaveAs2 PDF=17), re-uploaded to Cloudinary (`notes/converted/{id}.pdf`, raw type), notes updated (new `gdrive_id` + title extension → `.pdf`).
- Notes affected: 28, 30, 33, 35, 38, 39, 42, 45, 47, 49, 50, 52. All verified: valid `%PDF` magic, delivery HTTP 200.
- These notes now open in the pdfrx viewer with search + annotations; AI summaries now work on them too.
- Old `.ppt`/`.doc` originals kept on Cloudinary (tiny, ~12MB) as safety; can be deleted later.
- Future legacy uploads: app shows the honest "old binary format — open in another app" message (shrinking edge case).

## Previous Milestone: Infrastructure, AI RAG, Editors & Backup (2026-08-06)

### 0. Keep-Alive — Never Sleep Again
- `pg_cron` + `pg_net` schedule `keepalive-ping` every 5 min → hits `keepalive` edge function (real DB read). Verified HTTP 200 via `net._http_response`.
- App pings `/rest/v1/` every 15 min while running (`SupabaseKeepAliveService` in `services.dart`, hooked in DashboardPage).
- Migration `20260805010000_add_keepalive_cron.sql`. No UptimeRobot needed — ping runs inside Supabase itself.

### 1. Guest Mode — No Sign-In Wall
- App opens straight to the dashboard; `AuthService` auto-creates guest profile when no session.
- Sign-out drops to guest (stays in-app); "Sign In" menu item for guests.
- Guest AI history stored in SharedPreferences (fixes `22P02 invalid uuid: guest_user`).

### 2. PDF RAG — Notesy Reads the Library
- `chunks` table + `search_chunks_fts` made reproducible via migration `20260805000000_add_chunk_ingestion.sql` (DROP-first for the live function).
- `insert_chunk` / `insert_chunks` RPCs (SECURITY DEFINER, granted to anon+authenticated) — the app's only write path.
- App ingestion: `NoteService.indexForAi` (pdfrx text per page, batches of 10) on upload + donate; `ensureIndexedForAi` on first open; admin "Re-index Notes" bulk action.
- Fixed live `telegram_msg_id` NOT NULL without default (added DEFAULT 0).

### 3. AI Summaries
- Notesy `action: 'summarize'` — bypasses user rate limits, uses configured model, returns overview + key points.
- App: auto-generates on upload via rate-limited background queue (1 at a time / 2s apart, backs off after 5 failures); lazily on note-detail open.
- Summary card moved BELOW Full Description with a visible "Generating AI summary…" state; sparkle button regenerates.
- Verified live end-to-end via REST call.

### 4. Editor/Viewer Suite (mobile-first, offline)
- New `lib/editors/`: text_code_editor (flutter_code_editor + highlight, markdown preview, CSV table via `csv` 8.x), rich_text_editor (flutter_quill ≥11.5.1 — 11.5.0 crashes on Flutter 3.44), docx_editor_page + office_docx.dart (archive+xml read/write, **bold**/_italic_ markers), pptx_viewer_page + office_pptx.dart (zip+xml text; OLE2 binary .ppt detection), spreadsheet_editor (excel package grid + cell editing), image_editor_page (image package rotate/flip), video_player_page (chewie), audio_player_page (audioplayers).
- `FileViewerPage` rewritten as dispatcher with external-open fallback; save-back via `onSave` → Cloudinary re-upload + `updateNoteFileUrl`.
- Fixed: legacy bare Google Drive IDs resolve to `drive.google.com/uc`; extension derived from note title (Cloudinary URLs have none); graceful "file no longer available" for 401/403/404.

### 5. File Health & Storage Stats
- `NoteService.checkNotesHealth` — HEAD per file (5 concurrent), cached 12h (dead files 10 min) → red UNAVAILABLE badge on cards.
- Download logging: `log_download` RPC on note open → `downloads` table (migration `20260805020000_add_download_stats.sql`).
- Admin: `get_download_stats` + `get_storage_growth` → 14-day bar charts (bandwidth + storage growth), hand-rolled bars (no chart dep).
- `cloudinary-usage` edge function: 25-credit shared pool card (credits used, storage, bandwidth, plan) — the free tier is ONE pool: 1 credit = 1GB storage OR 1GB bandwidth/month.

### 6. Telegram Backup Storage
- `cloudinary-upload` now mirrors every file to the channel (`TELEGRAM_BOT_TOKEN`/`TELEGRAM_CHANNEL_ID` secrets) → returns `telegramMsgId`/`telegramFileId`; stored on the note (migration `20260806000000_add_telegram_backup.sql`).
- `telegram-restore` edge function: getFile → download → re-upload raw → update gdrive_id. Verified end-to-end (dead note revived, 200).
- Admin: "Restore from Backup" (auto-finds dead notes, restores each) + "Telegram backup coverage: X/Y" counter.
- Bot upload limit 50MB, download limit 20MB — fine for documents.

### 7. Local Docs (device documents)
- Permission flow: `MANAGE_EXTERNAL_STORAGE` (Android 11+) + `READ_EXTERNAL_STORAGE` legacy via permission_handler; one-time "Connect device storage" prompt → Android settings screen.
- Scan roots (Download/Documents/DCIM/root, depth 5, skips Android/.thumbnails), documents only (no images/media).
- Opens/edits files IN PLACE (no copies, no dual storage). Per-file: "Share to library" (explicit year/semester donate, covered by Terms) + "Keep offline copy".
- Imported tab = explicit copies for guaranteed offline.
- Policies updated in `policy_constants.dart` AND live `app_config` DB rows.

### 8. Settings Fixes (was mostly cosmetic)
- **App Font now applies** — `getThemeData` was ignoring `_fontFamily`; now loads via `GoogleFonts.getFont`.
- **Clear Cache** asks for confirmation.
- **Notification toggles wired** — master + sound toggles gate `showNotification`.
- **AI Usage Statistics** — real dialog (server counts vs daily limits, progress bars).
- **Export My Data** — shareable JSON (profile + notes) via share_plus.

### 9. Notes List Enhancements
- File-type filter (📇 icon next to view menu) — PDF red, DOC blue, PPT orange, XLS green, VID indigo, AUD pink, IMG purple, CODE blueGrey, TXT/MD teal, OTHER; combines with search + semester.
- Semester chips → single "Semester: All/1/2" dropdown; Local Docs chip next to All Notes.

### 10. Notesy Reliability
- No-tools fallback retry when Groq returns "Failed to call a function" (deployed).
- `NOTESCACHE_ANON_KEY` secret refreshed (stale key made logged-in users look like guests).

### 11. Infra/Build Fixes
- `androidx.cardview:cardview:1.1.0` never published → force-resolved to 1.0.0 for all modules in `android/build.gradle.kts`.
- `compileSdk = 37` + junction `android-37` → `android-37.0` (SDK manager naming).
- Windows CMake: `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for permission_handler_windows.
- Fixed Cloudinary Media Delivery ACL blocking ALL PDFs (`deny or ACL failure`) — user enabled "PDFs and zip files delivery" in console; upload function also stores docs as raw as insurance.

### 12. Commits (this era)
- `f88b23f` keep-alive, AI note indexing, guest mode, donate notes
- `25c6086` editors suite, local docs scan, AI summaries, usage stats, bug fixes
- `a6c75de` telegram backup storage + restore, PDF health fixes
- `01303f5` settings fixes (font, cache confirm, notifications, usage stats, data export, backup coverage)
- `ca9b7a1` PDF annotations via flutter_pdf_annotations + cardview fix, text selection
- `9649b54` PDF search (highlight + navigate matches)

### 13. Known Issues / Pending
- **FCM push** — notifications only fire while app is open/backgrounded; force-stop kills them. Biggest remaining gap.
- **PDF page-level editing** — no viable open-source path (pdfrx lacks public page ops; `pdf` 3.12 can't load existing files).
- **Backup coverage** — only notes uploaded after the Telegram feature have backups.
- **Play Store** — all-files access permission blocks store listing (fine for direct APK).
- **Kotlin built-in migration** warnings on every Android build (non-blocking for now).

---

## Previous Milestones

### 0. Edge Function Fixes
- Fixed circular reference `const selectedModel = isVision ? '...' : selectedModel` — caused 503 BOOT_ERROR
- Updated model from `llama-3.1-70b-versatile` (decommissioned) to `llama-3.3-70b-versatile`
- Added comprehensive error handling for tool calls (try/catch for arg parsing, tool execution, second Groq call)
- Fixed Enter key in AI chat — now creates new line instead of sending (use send button to send)

### 1. Chat Archiving System
- New `chat_archives` table in Supabase to track archived rooms
- `chat-archives` storage bucket (private, 5MB limit, JSON files)
- Auto-archiving: when a room exceeds 60 messages, oldest messages move to Supabase Storage as JSON
- Keeps last 50 messages per room in DB for fast access
- Admin Dashboard → "Archive Chats" button for manual cleanup
- Keeps DB under 500MB for 3000+ students

### 2. AI Chat History Persistence
- New `ai_chat_history` table (user_id, messages JSONB, updated_at)
- Chat history saved to Supabase after each message exchange
- Loaded on page open — conversation continues where left off
- Last 50 messages kept per student
- Only last 5 messages sent to Groq for context (saves tokens)
- Clear Chat button with confirmation dialog
- Guest users don't persist history

### 3. Pricing Page
- Three tiers: Free (KSh 0), Student Pro (KSh 250/month), Campus License (KSh 15,000/semester)
- M-Pesa payment dialog with STK push
- Feature comparison table
- FAQ section
- Admin Dashboard → "Pricing & Plans" button

### 4. Terms & Conditions + Privacy Policy
- Full Terms of Service (eligibility, account, content licensing, AI disclaimer, prohibited uses, M-Pesa billing, refunds, termination, Kenyan law)
- Full Privacy Policy (data collected, usage, third parties, security, user rights, guest mode, children)
- Saved to Supabase `app_config` table
- Editable from Admin Dashboard → App Content

### 5. Admin Dashboard — Full Config
- AI Settings: Model selector (70B/8B), Web Search toggle, daily limits
- Support & Contact: Help Center URL, email, phone, WhatsApp, WhatsApp Group Link, M-Pesa
- App Content: About Text, Terms & Conditions, Privacy Policy (multiline editors)
- Feature Gates: Communications Page Beta Lock toggle
- Admin Actions: Manage Users, Storage Explorer, Feedback, Push Update, Pricing, Archive Chats

### 6. WhatsApp Group Link
- New `whatsapp_group_link` config field in admin dashboard
- "Join WhatsApp Group" button in Profile → Settings
- Opens group link directly, shows "not configured" if empty

### 7. GitHub Push Prep
- Updated `.gitignore` with proper exclusions (`.env`, `supabase/functions/`, screenshots, dev files)
- Created `.env.example` with placeholder values
- Clean README.md (no internals exposed)
- Edge Function code excluded from git (proprietary AI logic)
- Removed sensitive files from git tracking

### 8. Scaling Analysis
- Free tier supports ~3,000-3,500 students (with Google Drive for files, caching, archiving)
- Bottleneck: database (500MB) — solved by chat archiving
- Edge Functions: 500K/month — solved by 70% cache hit rate
- Bandwidth: 5GB/month — solved by caching + Google Drive for files
- During exams (3x usage): ~2,000-2,500 students
- Supabase Pro ($25/month) handles 15,000+ students

### 9. System Test Script
- `test_everything.py` at `D:\Projekt\campus-ai\scripts\`
- Tests: connection, RLS policies, FTS search, cache, config, storage, rate limiting, profiles, notes, Edge Function
- 30 passed, 0 failed, 4 warnings (all expected)

### 1. Campus AI — RAG Search System
- **Document Processing Pipeline**: Built Python scripts (`D:\Projekt\campus-ai\scripts\`) that extract text from PDFs, PPTX, DOCX, and image files, chunk them into ~1000-word segments, and filter out PII (admission numbers, student names, emails, phone numbers).
- **Supabase Chunks Table**: Uploaded 298 test chunks from the research folder (`Class Notes Undergraduate Research Projects`) to the `chunks` table with full-text search (FTS) index.
- **FTS Search Working**: Tested queries like "research methodology", "sampling methods", "data analysis" — all return relevant lecture materials.
- **Edge Function RAG**: Modified `notesy` Edge Function (`supabase/functions/notesy/index.ts`) to:
  - Automatically search the `chunks` table before every Groq call
  - Inject relevant lecture materials into the system prompt as context
  - Added `search_lecture_docs` tool so the AI can explicitly search lecture materials when a student asks about a topic
- **Web Search**: Added DuckDuckGo API integration for off-topic questions. Toggleable from admin dashboard (`ai_web_search` config). Results sanitized and length-limited for security.
- **Model Selector**: Added admin dashboard toggle to switch between `llama-3.1-70b-versatile` (smarter) and `llama-3.1-8b-instant` (faster). Model choice saved in `app_config` table and read by Edge Function at runtime.

### 2. Profile Page — Full Overhaul
- **Avatar Upload**: Replaced the broken `updateProfileImage()` (which just generated DiceBear URLs) with actual Supabase Storage upload:
  - Path format: `{userId}/avatar.{ext}`
  - Magic byte validation (JPEG/PNG/WebP only)
  - 2MB file size limit (enforced client-side + storage bucket config)
  - RLS policies: users can only modify their own avatar folder
- **Default Avatars**: DiceBear identicon-style avatars for all users without custom photos. Used in profile page, chat rooms, and DMs.
- **Edit Tab**: Full Name + Bio editing with save button and loading state. Year Level dropdown (locked after first change). Theme settings: Light/Auto/Dark mode, 8 accent colors, 4 font choices.
- **Activity Tab**: Period selector (7 days / 30 days / All). Shows note uploads from the `notes` table.
- **Settings Tab — All Working**:
  - Change Password dialog (Supabase auth API)
  - Public Profile toggle (saves to `profiles.is_profile_public`)
  - Copy Friend Code (clipboard)
  - Report a Bug (opens FeedbackPage)
  - Help Center (opens URL from `app_config`)
  - Contact Support (email with `mailto:` prefix)
  - Call Support (phone with `tel:` prefix)
  - WhatsApp Support (wa.me link)
  - About dialog (from `app_config`)
  - Terms & Conditions dialog (from `app_config`)
  - Privacy Policy dialog (from `app_config`)
  - Delete Account (deletes avatar, notes, chats, AI usage, feedback, then signs out)

### 3. Admin Dashboard — Config Management
- **AI Settings Card**: Model selector (70B/8B), Web Search toggle, Daily text/image limits.
- **Support & Contact Card**: Help Center URL, Support Email, Phone, WhatsApp, M-Pesa — all editable.
- **App Content Card**: About Text, Terms & Conditions, Privacy Policy — all multiline editors with Save All button.
- **Admin Actions**: Manage Users, Storage Explorer, Feedback Explorer, Push Update (announcements).

### 4. Database Changes (SQL)
- `profiles.is_profile_public` column added (BOOLEAN, default true)
- `notes.user_id` column added (UUID, references auth.users)
- `storage.buckets` — `avatars` bucket created (2MB limit, JPEG/PNG/WebP)
- Storage RLS policies for avatar upload/update/delete/view

### 5. Security
- **Image Upload**: Magic byte validation prevents non-image files. Filename sanitized to `{userId}/avatar.{ext}`.
- **Prompt Injection Detection**: Existing in notesy — blocked patterns like "ignore previous instructions".
- **Web Search**: Results sanitized, length-limited to 2000 chars, no raw URLs exposed.
- **PII Filtering**: Python script strips admission numbers, student names, emails, phone numbers from document text before uploading.
- **Rate Limiting**: Per-user daily AI usage tracking via `user_ai_usage` table.
- **Delete Account**: Full cleanup — removes avatar, notes, chats, AI usage, feedback before signout.

### 6. Known Issues / Pending
- **Telegram Storage**: Bot `@notescache_bot` authenticates but can't send to channel — "Chat not found". Needs bot added as admin. For now, chunks stored directly in Supabase (no Telegram needed for RAG).
- **Remaining Docs**: Only research folder processed. Full doc collection (external drive + phone + school Telegram group) pending.
- **Activity Tracking**: `notes` table needs `user_id` column populated for existing notes. New uploads should include it.
- **Delete Account**: Deletes data from tables but doesn't call Supabase Admin API to delete the auth user itself. Contact Supabase support for full deletion if needed.

---

## Previous Milestones

### PDF Engine Overhaul & Guest Lockdown (2026-04-26)

### 1. In-App Document Experience
- **PDF Engine Upgrade**: Swapped `syncfusion` for the lightweight and lightning-fast `pdfrx` engine.
- **Gallery Mode**: Added a full-screen, swipeable gallery view for mobile reading comfort.
- **Page Extraction**: Built a "Snipper" tool allowing students to export and share specific PDF pages as high-resolution images (`share_plus`).
- **Smart Metadata Detection**: Removed unreliable file extension guessing. The app now directly queries Google Drive metadata to flawlessly route `.txt` files to the in-app editor and Office files to native device viewers.
- **Orientation Lock**: Added manual Landscape/Portrait toggles for distraction-free reading.
- **Academic Notes View**: Added a drop-down view switcher (List, Detailed, Compact) for browsing notes.

### 2. Guest Mode & Privacy Lockdown
- **Persistent AI Limits**: The 3-message limit for guest AI chats is now saved in `SharedPreferences`, surviving app restarts.
- **Social Blocks**: Guests are officially blocked from creating groups, adding friends, or viewing other users' activities.
- **View-Only Access**: Guests can browse the note repository but are restricted from opening or downloading materials.

### 3. Roles & Branding
- **Multi-Role Mastery**: Admins can now hold multiple roles (e.g., Admin + Lecturer + Student) simultaneously.
- **Custom App Icons**: Integrated `flutter_launcher_icons` to replace default Flutter icons with the official NotesCache branding across Windows and Android.
- **UI Clean-up**: Streamlined the Dashboard by removing redundant logos.

## Latest Milestone: Auth Stability & Global Notifications (2026-04-26)

### 1. Authentication & Account Recovery
- **Custom SMTP Integration**: Bypassed Supabase's free tier limits by linking a custom Gmail SMTP server. Sign-up and recovery emails are now unlimited.
- **Forgot Password Flow**: Implemented a complete password reset workflow in `login_page.dart`.
- **Web Landing Page**: Built and deployed a premium landing page at `notescache-reset.netlify.app`. It serves as the official project site and handles password resets/email confirmations via an intelligent overlay.
- **Implicit Auth Flow**: Switched to implicit auth to ensure seamless handshakes between the Flutter mobile app and the Netlify web handler.

### 2. Global Notification System
- **Desktop Alerts**: Integrated `local_notifier` to trigger native Windows toast notifications.
- **Real-time Subscriptions**: Added background listeners in the Dashboard for new messages, lecturer uploads, and admin announcements.
- **Graceful Failures**: Wrapped notification initialization in try-catch blocks to prevent app crashes during hot restarts or missing native plugin links.

### 3. Admin & Content Management
- **Broadcast System**: Added a "Post App Update" section in the Admin Dashboard, allowing admins to send global push alerts and news feed items instantly.
- **App Updates Feed**: Created a dedicated `UpdatesPage` accessible from the user profile menu to track all official app news.

## Latest Milestone: App Stabilization & Security Hardening (2026-04-28)

### 1. Chat & Read-Receipts
- **Sync Fix**: Resolved the "sticky" unread message bug. Chat rooms now accurately sync `last_read_at` timestamps on exit, ensuring badges clear instantly.
- **Clock Skew Protection**: Implemented UTC-based timestamp comparisons with safety padding to handle millisecond differences between client devices and the Supabase database.

### 2. Native Mobile Readiness
- **Notification Permissions**: Integrated active permission requests for Android (POST_NOTIFICATIONS) and iOS.
- **Manifest Updates**: Hardened `AndroidManifest.xml` with required permissions for internet, vibration, and background alerts.

### 3. Service Reliability
- **Realtime Optimization**: Refactored the notification listener logic in `DashboardPage` to prevent race conditions during session recovery.
- **Broadcast Stability**: Verified that global admin announcements trigger native alerts for all users upon document/update insertion.

### 4. Notesy AI Hardening
- **Daily Quotas**: Implemented a per-user daily message cap (20 messages/day) to prevent API abuse and manage costs.
- **System Instructions**: Updated the AI persona (Notesy) with stricter academic boundaries and safety filters.

## Latest Milestone: Settings Page Overhaul (2026-06-09)

### 1. Full Settings Page Rewrite
- **Every button now works** — no dead or non-functional UI elements.
- **Appearance**: Theme Mode, Primary Color, App Font (existing). Added **Text Size** slider (0.7×–1.5×) with app-wide `MediaQuery` override.
- **Account section** (NEW): Edit Profile link (navigates to ProfilePage), Change Password (Supabase auth API dialog), Public Profile toggle, Delete Account with "DELETE" confirmation.
- **Notifications**: Push Notifications toggle (persisted to SharedPreferences), Email Updates toggle (formerly unused — now functional and persisted), Notification Sound toggle (NEW), Test Notification button.
- **AI & Usage section** (NEW): Notesy info card, Usage Statistics placeholder.
- **Data & Storage section** (NEW): Live cache size calculation, Clear Cache, Auto Backup toggle, Export My Data placeholder.
- **Support & About**: Report a Bug, Help Centre, Support M-Pesa, Privacy Policy (fallback text when config missing), Terms of Service (NEW with fallback), About NotesCache (fallback text).
- **System section** (NEW): Reset to Defaults — clears all local preferences and resets theme + font + text scale.
- All toggles persisted via `SharedPreferences`.

### 2. Text Scaling — App-Wide
- Added `textScale` field + getter + setter + persistence to `ThemeProvider` in `services.dart`.
- Wired into `main.dart` via `MaterialApp.builder` with `MediaQuery.textScaleFactor` override.
- Slider in Settings → Appearance → Text Size syncs instantly across the app.

### 3. Cleanup
- Removed unused `_emailUpdates` flag and `_prefTextScale` constant.
- Removed dead `_setDoublePref` helper.
- Profile visibility toggle now syncs initial state from `AuthService.currentUser.isProfilePublic`.

## Next Steps
- Implement full background push notifications via FCM for when the app is completely closed.
- Finalize production deployment builds for Android (APK) and Windows (EXE).
- Begin Beta testing with the student user group.


