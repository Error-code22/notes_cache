# NotesCache

A campus study companion app built with Flutter and Supabase. Access lecture notes, chat with classmates, and get AI-powered study help — all in one place.

## Features

- **Note Library** — Browse and upload lecture notes organized by year and semester
- **AI Assistant (Notesy)** — Ask questions, get explanations, generate flashcards
- **Chat Rooms** — Connect with classmates through group and direct messages
- **Friend System** — Find and connect with other students via friend codes
- **Profile & Themes** — Customizable profile with themes, fonts, and avatar upload
- **Admin Dashboard** — Manage users, content, AI settings, and app configuration

## Tech Stack

- **Frontend**: Flutter (Dart)
- **Backend**: Supabase (PostgreSQL, Auth, Storage, Edge Functions)
- **AI**: Groq API (Llama 3.1)
- **Storage**: Google Drive, Supabase Storage
- **Payments**: M-Pesa

## Getting Started

### Prerequisites

- Flutter SDK 3.44+
- Supabase account (free tier works)
- Groq API key

### Setup

1. Clone the repository
2. Copy `.env.example` to `.env` and fill in your credentials
3. Run `flutter pub get`
4. Run `flutter run -d windows` (or `-d android` for mobile)

### Database Setup

Run the SQL migrations in your Supabase SQL Editor to create the required tables and functions.

## Project Structure

```
lib/
├── main.dart              # App entry point
├── services.dart          # Business logic & state management
├── models.dart            # Data models
├── dashboard_page.dart    # Main dashboard
├── notes_page.dart        # Note browsing
├── ai_chat_page.dart      # AI assistant
├── chats_list_page.dart   # Chat rooms list
├── chat_room_page.dart    # Individual chat
├── profile_page.dart      # User profile & settings
├── admin_dashboard_page.dart  # Admin panel
├── login_page.dart        # Authentication
└── pricing_page.dart      # Subscription plans
```

## License

Proprietary. All rights reserved.

## Contact

- Email: support@notescache.com
- WhatsApp: +254 700 000 000
