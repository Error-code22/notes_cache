# NotesCache Development Progress

## [2026-04-25] Project Genesis & Architecture
- Initialized Flutter project `notes_cache`.
- Set up Premium Design System (Deep Navy & Amber).
- Implemented core models (User, Note, Role).
- Integrated `provider` for state management.

## [2026-04-25] UI Foundation
- Built Identity Selection (Mock Auth) for testing.
- Created Premium Dashboard with horizontal filter chips (Kotlin-inspired).
- Added Search Bar and Filter UI components.

## [2026-04-25] Backend Integration (Supabase)
- Added `supabase_flutter` and `flutter_dotenv`.
- Migrated keys from old project (Supabase, Gemini, Groq, Cloudinary, Telegram).
- Configured `.env` and `.gitignore` for security.
- Initialized Supabase in `main.dart`.
- Migrated to new Supabase project (`wgxsumbvhzwljxyozdsd`).

## [2026-04-25] Perfecting Auth
- Replaced Mock Auth with **Real Supabase Authentication**.
- Built Login/Signup form with **Academic Year** and **Full Name** support.
- Set up Supabase **SQL Trigger** for automatic profile creation.
- Implemented **Year-Locked Filtering** (Students only see notes for their year).

## [2026-04-25] Storage Strategy & Research
- Evaluated **Telegram vs Google Drive** for academic storage.
- Decided on **Direct Google Drive Link (OAuth)** after successfully bypassing the Service Account quota limitation.
- Successfully verified "Direct Link" by uploading `Direct_Link_Test.txt` from the Flutter app to the admin's personal GDrive folder.
- Established "Drive Pooling" readiness: The architecture now supports linking multiple accounts for infinite storage.
- Identified data usage constraints for mobile users (avoiding double-uploads).

## [2026-04-25] Admin Infrastructure
- Created **Admin Dashboard (Command Center)** for system-wide management.
- Implemented **Role-Based Access Control (RBAC)** in the UI: Admins see specific management tools.
- Added Stats overview for Users, Notes, and Storage.

## [2026-04-25] UX & Quality of Life
- Implemented **Session Persistence**: Users stay logged in across restarts/hot reloads.
- Added **Keyboard Support**: Login form now supports "Enter" key for submission.
- Implemented **Profile Dropdown UI**: Premium profile menu in the AppBar.
- Added **Logout Confirmation**: Safety dialog to prevent accidental sign-outs.
- Replicated **Kotlin Profile Design**: Added Bio, Interests, and Tabbed UI to match the original StudySphere layout.
- Integrated **Windows Documents Folder**: App now defaults to `Documents\NotesCache` for all local storage and downloads.
- Analyzed **Spotilark Flutter Architecture**: 
    - Audio: `just_audio` + `audio_service` for background play.
    - Storage: YouTube scraping + Telegram-as-a-Database for unlimited free MP3 hosting.
    - Media: Cloudinary for optimized cover art.
