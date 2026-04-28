# Pending Fixes & Improvements

The following items need to be addressed in the next session to stabilize the app for production:

### 1. Chat System: Unread Message Persistence
- **Issue**: The notification of unread messages persists even after reading them.
- **Goal**: Ensure the unread count in `chats_list_page.dart` correctly syncs with `room_member_metadata` and clears immediately upon exiting a chat room.

### 2. Mobile Notifications
- **Issue**: Push notifications are currently only functional on Windows (via `local_notifier`). Mobile devices (Android/iOS) are not receiving alerts.
- **Goal**: Integrate Firebase Cloud Messaging (FCM) or Supabase Edge Functions to trigger native mobile push notifications.

### 3. Update Broadcasts
- **Issue**: When an admin posts an "App Update", notifications are not triggering reliably, even on desktop.
- **Goal**: Verify the Realtime subscription in `dashboard_page.dart` for the `app_updates` table and ensure the payload is correctly passed to `NotificationService`.

### 4. Notesy AI Security
- **Issue**: Need to harden the AI chat interface.
- **Goal**: Implement stricter daily limits and content filtering to prevent abuse of the AI service.

---
*Note: Last session ended after implementing custom SMTP for unlimited auth emails and a web-based password reset/confirmation landing page.*
