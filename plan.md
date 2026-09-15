# NotesCache Plan 🗺️

Status as of **2026-08-18**. Anything in a checkbox list without ✅ is next up.

## 🎯 Web — current focus (site is a simple landing + /view; not close to done)

- [ ] **Decide the web's future**: simple download hub (current) vs. notes browsing (needs anon read policy + web login) vs. full app replica (was tried 2026-08-18, homepage glitched — code preserved in git `2de5382..4e8a3ae`, reverted in `f77c9ee`).
- [ ] **Website UI polish** — hero, features, roadmap, downloads, footer with terms/privacy.
- [ ] **Terms/privacy on web?** — migrate from in-app dialogs or keep in-app only.
- [ ] **Web PPTX/XLSX rendering** — JS libs are paid/limited; app remains the full reader.

## 🎯 Next up — Notesy retention features

1. [ ] **Notesy voice replies (TTS)** — Notesy reads answers aloud (`flutter_tts`, free). Killer for studying on the go.
2. [ ] **Flashcards → Memory Lab** — one-tap "save these flashcards" from Notesy into a real deck.
3. [ ] **"Ask about this note"** — from note detail, jump into Notesy with the note's context preloaded.
4. [ ] **Share chat** — export a conversation as text/image to share with classmates.
5. [ ] **Weekly study summary** — "This week: X topics, Y questions, Z downloads" (activity data exists).

## 🎯 Notesy voice (researched 2026-08-18 — stays on Groq, no new keys)

- [ ] **Voice dictation** — mic button in chat input → record → Groq `whisper-large-v3-turbo` transcribes (`/audio/transcriptions`) → text into the chat box or sent directly. `record` package for capture; keys stay in edge function secrets.
- [ ] **Voice replies** — speaker button on each Notesy reply → Groq `canopylabs/orpheus-v1-english` TTS (`/audio/speech`) → audio bytes back → play via audioplayers (already in deps). Same audio pipeline, reverse direction.
- [ ] **New `notesy` actions**: `transcribe` (audio → text) and `speak` (text → audio).
- [ ] Privacy note: audio goes to Groq for transcription — same trust level as existing text; user's voice passes through briefly.

## 🎯 Full document reader (in-app, native parsers)

- [ ] **ODT** — zip+xml `content.xml` → paragraphs (same pattern as DOCX).
- [ ] **ODS** — zip+xml → table grid (reuse xlsx grid UI).
- [ ] **ODP** — zip+xml → slides (same as PPTX pattern).
- [ ] **RTF** — parse control words → plain text.
- [ ] **EPUB** — zip → xhtml → text reader.
- [ ] Legacy binary DOC/XLS stay device-viewer fallback (OLE2, not worth parsing).

## 🎯 Web tier 3 (parked — big)

- [ ] **Full web app** (auth + notes + year isolation + Notesy in browser) — essentially rebuilding the Flutter app in React. RLS blocks guest note reads → needs web login. Only if a real web product is wanted.
- [ ] **Web PPTX/XLSX rendering** — their JS libs are paid/limited; app remains the full reader for now.
- [ ] **Cloudinary fl_pdf / server-side conversion** for web previews of non-streamable formats.

### Also queued
- [ ] **FCM push notifications** — biggest gap (notifications die when app force-stopped).
- [ ] **Batch AI summaries for old notes** — 39/47 notes missing summaries; one admin button.
- [ ] **Telegram backup backfill** — 0/47 notes backed up; `telegram-restore` currently useless.
- [ ] **Terms/privacy on website?** — decide whether to migrate from in-app dialogs to web pages (keep in-app for now).
- [ ] **v1.0.4 GitHub release upload** — tag + APKs + Windows zip built; user must publish (no token).

## ✅ Done (recent era — 2026-08-13)

- **Web viewer + PWA** — installable on iPhone/Mac (manifest+SW+iOS meta), `/view` document viewer (PDF streams, DOCX via docx-preview, images/audio/video native), app "View on Website" bridge with `?ext=`.
- **Homepage "What's Coming" button** → full roadmap page.
- **Android 11+ browser intent fix** (explicit `<queries>`).
- **Next.js workspace-root warning fixed** (turbopack.root).

## ✅ Done (v1.0.4 feature set — 2026-08-12)

- **Public launch**: repo public, GitHub release v1.0.0 (3 clean APKs), landing page live at **notescache.netlify.app**, direct-download link for WhatsApp groups.
- **Secret-leak cleanup**: `.env` stripped to public-only, git history purged, APKs rebuilt + verified secret-free, all leaked keys rotated (Groq/Cloudinary/Telegram/Supabase; GCP disabled by Google; Gemini ignored).
- **notescache-web**: rebuilt as a minimal Next.js static download hub (old full-web-app source was lost — intentionally not rebuilt; web app "coming soon").
- **Legacy Office migration**: all 12 old `.ppt`/`.doc` notes converted to PDF (local Office 2019) and re-uploaded — now open in the PDF viewer. Cloudinary conversion tested and proven unavailable; no hosting added.
- **Keep-alive**: pg_cron → keepalive function every 5 min + in-app 15-min ping. Project never pauses.
- **Guest mode**: no sign-in wall; auto-guest; guest AI history local; 3-message cap.
- **PDF RAG**: uploads index into `chunks`; old notes index on first open; admin re-index.
- **AI summaries**: auto on upload (background queue) + lazily on note-detail open; cached in DB; shown under Full Description with "Generating…" state.
- **Editor/viewer suite** (mobile-first, offline-capable):
  - PDF: pdfrx viewer (text selection, search w/ highlights + prev/next + match counter) + native annotation editor (flutter_pdf_annotations: pen/highlight/stamps).
  - DOCX editor (custom archive+xml round-trip), PPTX text viewer (binary .ppt → clear message), XLSX grid editor, CSV RFC-4180 table, code/md/txt editors, image editor (rotate/flip), video player, audio player.
  - Save-back: edits re-upload to Cloudinary and update the note.
- **Telegram backup**: every upload mirrored to the channel; `telegram-restore` + admin "Restore from Backup"; admin backup-coverage counter.
- **Storage tracking**: Cloudinary usage card (25-credit shared pool), 14-day bandwidth + storage-growth charts, per-note download logging.
- **File health**: automatic HEAD checks → UNAVAILABLE badges (dead files re-checked every 10 min).
- **Local Docs**: one-time all-files permission → device scan (documents only) → open/edit in place; explicit per-file "Share to library" + "Keep offline copy"; policies updated (live DB + constants).
- **Settings fixed**: App Font actually applies; Clear Cache confirmation; notification toggles wired; AI Usage Stats dialog; Export My Data (JSON share).
- **Notes list**: file-type filter (card colors), semester dropdown, search.
- **Notesy fixes**: no-tools fallback on Groq tool-call failures; guest history → SharedPreferences (no 22P02).
- **Infra**: cardview 1.1.0 force → 1.0.0; compileSdk 37 junction; Windows coroutine define; flutter_quill ≥11.5.1.

## ⏳ In progress / queued

- [ ] **v1.0.2 release** — bundle the recent fixes: guests blocked from uploads, demo-mode banner, theme toggle (first-click) fix, desktop Local Docs folder picker, lazy 1850-doc list, in-app updater, clearer card wording. Rebuild APKs + Windows zip → upload → users get the in-app update toast automatically.
- [ ] **Phone test pass** of the current build — search, annotations, offline, editors, updater.
- [ ] **DOCX/PPTX visual rendering (no server)** — replace the flat-text docx editor with a WebView renderer using `docx-preview.js` + `pptxviewjs` (server-free, real fonts/tables/layout). **View + annotate model** (same as PDF). Editing note: keep the text editor as edit mode, WebView as preview mode.
- [ ] **FCM push notifications** — notifications die when the app is force-stopped. Firebase project + service. The only major functional gap.
- [ ] **Admin "Re-index Notes"** — never actually clicked; old notes pile pending.
- [ ] **Delete old .ppt/.doc originals** from Cloudinary (~12MB, currently kept as safety).

## ✅ Done (recent, not yet released to users — ships in v1.0.2)

- **In-app updater (Happymod-style)** — checks GitHub latest release on app open; "Update available" dialog → download → system installer. No new dependencies.
- **Guests blocked from library uploads** (FAB + page gate; Donate remains the anonymous channel).
- **Theme toggle fixed** — first click from system mode now actually changes theme (was an invisible no-op).
- **Desktop Local Docs** — folder picker replaces the phone-style scan on Windows.
- **Local Docs lazy list** — 1850+ docs scroll smoothly.
- **Demo-mode yellow banner** on dashboard for guests.
- **Card wording clarified** — Academic Notes = browse/read; Donate = contribute.
- **Email confirmation disabled** — signups are instant now (was the launch blocker).

## 🔮 Later / conditional

- [ ] **Offline AI (maybe)** — on-device model (llama.cpp via `flutter_llama` / MediaPipe `ai_edge`; 1B–3B Q4 ≈ 300MB–1GB download). Researched 2026-08-18: feasible & production-ready, BUT poor fit now — users on limited bundles, big quality gap vs cloud 70B, offline RAG needs local embeddings. If ever: opt-in download pack, "offline mode = simpler answers" label, hybrid routing (cloud when online). Cheaper first step: offline conversation cache (read past Notesy chats offline).
- [ ] **Desktop workspace dashboard** (designed, not yet built — mockup reviewed):
  - Shell: sidebar nav (Dashboard/Notes/Communication/Memory Lab), top bar with ⌘K-style search, split main view — standard desktop grammar, all Flutter-native (no new plugins)
  - Widgets and their honest data sources:
    - Resume Learning banner → needs **last-opened-note logging** (new, small: log note opens, resume from last file)
    - Workspace navigation cards → already exist (real)
    - Daily Flashcard widget → pull from existing Memory Lab quiz generator (real, wiring only)
    - Recent Activity → real today (uploads via getUserActivity); quiz/chat events come later
    - Focus Timer → new, self-contained (dart:async only)
  - Rule: no fake data widgets (learned from the mock cleanup). Build shell with real data first, placeholder-labeled widgets after.
  - Reuse brand colors (indigo seed, not the mock's purple); responsive: sidebar collapses to bottom nav on mobile.
- [ ] **Notesy grounding upgrades** (when AI feedback arrives; all free/keyless):
  1. **Semantic search on chunks** — embeddings instead of keyword-only FTS so Notesy finds concepts, not just words (the real differentiator: it knows *this campus's* notes)
  2. **Academic APIs** — arXiv + Crossref tools (free, reputable, no keys) for scholarly answers
  3. **Better web search** — replace DuckDuckGo instant-answer with real result snippets (keyless HTML search or free-tier API); existing sanitization + admin toggle already cover guardrails
- [ ] **R2 swap** — when Cloudinary's 25-credit/month pool starts hurting. `r2-upload` edge function already exists.
- [ ] **PDF page-level editing** (delete/reorder/merge/split) — blocked: pdfrx has no public page-manipulation API and `pdf` 3.12 can't load existing files. Revisit when either changes.
- [ ] **PDF form filling / OCR / password** — no viable free path today.
- [ ] **Play Store decision** — `MANAGE_EXTERNAL_STORAGE` (Local Docs scan) blocks Play Store listing; fine for direct APK installs.
- [ ] **Kotlin built-in migration** — will be required by future Flutter versions (warning on every build).
- [ ] **iOS build** — not started.
- [ ] **Backfill old notes into Telegram backup** (only notes uploaded after the feature have copies).
- [ ] **Desktop annotate/editing** — flutter_pdf_annotations is mobile-only; desktop uses external tools.

## Done-but-caveated (watch items)
- flutter_pdf_annotations is a brand-new (April 2026) MIT plugin — test on real devices before trusting important docs.
- Cloudinary Media Delivery ACL was blocking all PDFs (`deny or ACL failure`); fixed via console checkbox ("PDFs and zip files delivery") + raw-type uploads as insurance.

## Architecture Review — 2026-09-11

Assessment against multi-year notes app architectural recommendations.

### 1. Flat metadata + tags, not folder hierarchy
**✅ Covered.** Notes are flat DB records (`notes` table) with `target_year`, `semester`, `lecturer_name`, `category`, and `content` columns. No nested folder structure. Cross-cutting queries work — RLS filters by year level but `ilike` search spans all notes the user can see. No `tags` or `topic`/`unit_code` columns exist yet, but the schema is flat and additive — adding a `tags TEXT[]` column or `unit_code TEXT` column is trivial without restructuring. The `donated_notes` table mirrors the same flat pattern.

### 2. Metadata/file separation
**✅ Covered.** Files live in Cloudinary (object storage) — the `notes` table stores only `gdrive_id` (Cloudinary public ID or Google Drive ID) and `file_size`. No raw file bytes in the DB. Telegram backup is a secondary blob store, also reference-only (`telegram_msg_id`, `telegram_file_id`). The DB never stores file content — `content` is the extracted text body, not the binary.

### 3. Full-text search on note content
**⚠️ Partially covered.** Title search exists (`ilike('title', ...)`) but content search does not — `content` column (extracted text) has no GIN/FTS index. The `chunks` table has FTS for AI RAG, but that's separate from user-facing search. The `donated_notes` table has a GIN index on `title` but not `content`. Gap: user-facing search is title-only; adding `to_tsvector` on `notes.content` would enable full-text search without changing the UI.

### 4. Content-addressable storage / dedup
**⚠️ Partially covered.** `findDuplicateNote` checks file size + fuzzy title match before upload and prompts the user. This is metadata-level dedup, not content-addressable — if two users upload the same file with different titles, it creates two Cloudinary blobs. True hash-based dedup (SHA-256 on upload, reuse existing blob) doesn't exist. Cloudinary 25-credit pool is the cost pressure; hash dedup would reduce storage but is not urgent at current scale.

### 5. Offline-first as default
**⚠️ Partially covered.** Notes list is cached to SharedPreferences (metadata only). "Download All for Offline" is an explicit opt-in bulk download. The app doesn't block on network for reads (cached metadata + local file fallback), but writes (uploads) always require network. New notes are not written locally first with background sync — the upload flow goes straight to Cloudinary + Supabase. The offline model is "read cached, download on demand" not true local-first with sync.

### 6. Versioning instead of overwrite on reupload
**❌ Not covered.** When a note is re-uploaded (e.g., editor save-back), `updateNoteFileUrl` overwrites the existing Cloudinary blob and updates the DB record in place. No prior versions are retained. The `chunks` table replaces old chunks on re-index. No version history exists anywhere — a student who overwrites a note loses the old version permanently.

### 7. Cold storage tiering for old years
**⚠️ Partially covered (schema-compatible).** The `target_year` column on `notes` already partitions data by year. When a student graduates, their year's notes could be flagged or moved to cheaper storage (R2 cold tier, or a `archived BOOLEAN` column). The flat schema supports this without rewrite. No implementation exists yet — noted as future consideration, appropriate for current scale.

### 8. Operational hardening
**⚠️ Partially covered.** (a) Secrets in `.env` were cleaned up — only public values (Supabase URL/anon key, Google client IDs) ship in the APK. Groq/Cloudinary/Telegram keys are in edge function secrets only. **However**, `GOOGLE_DRIVE_CLIENT_ID` and `GOOGLE_DRIVE_CLIENT_SECRET` are still in `.env` — the client secret is not truly secret for OAuth web flows, but worth noting. (b) No pre-commit or CI secret scanner exists — the leak was caught by external scanners after going public. (c) Search debounce exists in `notes_page.dart` and `donate_notes_page.dart` (350ms `Timer`). Config caching was flagged in the speed audit but `getAppConfig()` still hits Supabase on every call with no in-memory cache — 8+ call sites, no memoization.

### 9. Long-retention account model
**⚠️ Partially covered.** Data export (JSON share) and full account delete (avatar, notes, chats, AI usage, feedback, profile) both work. Supabase auth handles password recovery via email. **Gaps for 4-year retention**: (a) Google OAuth refresh tokens are stored locally and expire — no server-side refresh mechanism; if a user changes Google accounts or clears app data, they could lose access. (b) Email changes are not supported — if a student's university email deactivates after graduation, account recovery depends on that email. (c) No account migration path if Supabase changes its auth provider. These are low-risk for a 4-year span but worth noting for true long-retention.
