# Project Progress Log 🚀📈

## Latest Milestone: PDF Engine Overhaul & Guest Lockdown (2026-04-26)

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

## Next Steps (See next_fixes.md)
- Fix unread message persistence (read-receipt sync).
- Implement native mobile push notifications (FCM/Supabase Edge).
- Verify Admin Update triggers for all user roles.
- Harden Notesy AI security and daily limits.

