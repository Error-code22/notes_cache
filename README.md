# NotesCache

**Many notes. One place.** — A campus study companion for students.

NotesCache is a Flutter app that puts your lecture notes, AI-powered study help, and classmate connections in one place. Browse notes by year and semester, ask Notesy (your AI study ally) anything, and chat with friends — all free.

[![Download on Android](https://img.shields.io/badge/Download-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-arm64-v8a.apk)
[![Download on Windows](https://img.shields.io/badge/Download-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/Error-code22/notes_cache/releases/latest/download/NotesCache-Windows.zip)
[![Visit the site](https://img.shields.io/badge/Website-notescache.netlify.app-4A90D9?style=for-the-badge)](https://notescache.netlify.app)

---

## Features

### 📚 Note Library
- Browse and search lecture notes organized by **year and semester**
- File-type filters (PDF, DOC, PPT, XLS, video, audio, images, code)
- Download notes for **offline reading**
- File health checking — dead links get an UNAVAILABLE badge automatically

### 🤖 Notesy — AI Study Assistant
- Ask questions about your notes, homework, or any topic
- **Vision support** — attach up to 3 images/screenshots (Qwen 3.6 27B)
- **RAG-powered** — Notesy searches your campus's actual lecture documents
- Study tools: memory hooks, flashcards, quizzes, revision plans, recall drills
- **Chat history** — multi-conversation sidebar with pin/rename/delete
- **Vault mode** — biometrics/PIN-protected private chats with decoy protection
- Web search when your notes don't have the answer

### 💬 Communication
- Chat rooms and direct messages with classmates
- Friend system with shareable friend codes
- Unread badges, read receipts

### ✏️ Full Document Suite
- Built-in viewers/editors: **PDF** (with search + annotations), DOCX, PPTX, XLSX, CSV, code/text, images, video, audio
- Edit a document and save it back to the library
- **Local Docs** — browse and open documents from your own device

### 🎨 Personalization
- Custom themes: light/dark/auto, accent colors, fonts
- Profile with avatar (custom photo or DiceBear), bio, year level
- Google Sign-In or email/password — link both on one account

### 👨‍🏫 Admin Dashboard (for staff)
- User management, feedback explorer, AI controls with model tester
- Cloudinary storage monitoring, usage charts
- App announcements, pricing plans, feature roadmap management

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Flutter (Dart) — Android, Windows |
| **Backend** | Supabase (PostgreSQL, Auth, Edge Functions, Storage) |
| **AI** | Groq (Llama 3.3 70B, Qwen 3.6 27B vision) |
| **File storage** | Cloudinary (+ Telegram backup mirror) |
| **Distribution** | GitHub Releases + Netlify landing page |

## Getting Started

### Prerequisites
- Flutter SDK 3.44+ (Dart 3.12)
- A Supabase project (free tier works)
- Groq API keys

### Setup
```bash
# 1. Clone
git clone https://github.com/Error-code22/notes_cache.git
cd notes_cache

# 2. Configure environment (public values only — see SECURITY note below)
cp .env.example .env
#   fill SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_WEB_CLIENT_ID

# 3. Run
flutter pub get
flutter run -d windows   # or -d <android-device>
```

### Database setup
Apply the migrations in `supabase/migrations/` to your Supabase project, then deploy the edge functions:
```bash
supabase db push --linked
supabase functions deploy notesy
supabase functions deploy cloudinary-upload
supabase functions deploy telegram-restore
supabase functions deploy cloudinary-usage
supabase functions deploy keepalive --no-verify-jwt
```

Server secrets (Cloudinary API secret, Telegram bot token, Groq keys, Supabase service keys) go in **Edge Function secrets** — never in `.env`:

```bash
supabase secrets set CLOUDINARY_API_SECRET=... TELEGRAM_BOT_TOKEN=... GROQ_KEY_RYAN=...
```

> **⚠ SECURITY:** `.env` is bundled into the APK as an asset. It must only ever contain **public** values (Supabase URL/anon key, Google client IDs). Server credentials live exclusively in Supabase Edge Function secrets.

## Project Structure

```
lib/
├── main.dart                  # App entry point
├── services.dart              # Business logic, auth, AI, updater, connectivity
├── models.dart                # Data models
├── dashboard_page.dart        # Main dashboard (homepage)
├── notes_page.dart            # Note library
├── ai_chat_page.dart          # Notesy AI (multi-chat, vault, vision)
├── chats_list_page.dart       # Chat rooms / DMs
├── chat_room_page.dart        # Individual chat
├── profile_page.dart          # Profile, edit dialog, DiceBear avatars
├── admin_dashboard_page.dart  # Admin grid (12 modules)
├── login_page.dart            # Auth (email + Google)
├── local_docs_page.dart       # Device document browser
├── editors/                   # DOCX/PPTX/XLSX/CSV/code/image/video/audio
└── supabase/functions/        # Edge functions (notesy, upload, restore...)
```

## Releases

- **v1.0.4** — Notesy overhaul: 3-image vision, chat history sidebar, vault mode with decoy, pill input, beta notices, speed optimizations, RLS security hardening
- **v1.0.3** — Google Sign-In, admin dashboard redesign, account linking, offline startup fix
- **v1.0.2** — In-app updater, admin updates manager, feedback explorer fix
- **v1.0.1** — Android 7+ support, Windows build, guest mode fixes
- **v1.0.0** — Public launch

## Roadmap

See the live roadmap at [notescache.netlify.app](https://notescache.netlify.app) or in the app (homepage → "What's Coming"). Up next: voice replies, flashcards to Memory Lab, note-context AI, chat sharing, weekly study summaries, push notifications.

## License

Proprietary. All rights reserved.
