class AppPolicies {
  static const String termsAndConditions = """
Foluma Terms & Conditions
Effective Date: November 6, 2026

1. Acceptance of Terms
By accessing or using Foluma, you agree to these terms. If you are using the app as a student, lecturer, class rep, or guest, you must adhere to academic integrity standards.

2. User Accounts
- Users must provide accurate information (Name, Email, School, Programme, Academic Year and Semester).
- You are responsible for maintaining the confidentiality of your account.
- Guest accounts have limited functionality and AI usage.

3. Content & Intellectual Property
- You retain ownership of the notes you upload.
- By uploading a note and confirming the sharing notice, you grant Foluma a licence to store, display and distribute that note to students in your programme and to staff who manage the relevant units.
- Shared notes are uploaded to our cloud storage (Cloudflare R2), backed up to Telegram, and may be processed by the AI providers listed in the Privacy Policy so Foluma AI can answer questions about them.
- Private notes stay visible only to you by default. They use the same private cloud storage, but are never copied to the Telegram backup and are not indexed for AI unless you explicitly allow AI access to that note.
- No copyrighted material may be uploaded without the owner's permission.

4. Notesy AI Service
- AI features are provided for academic assistance and are online-only.
- AI queries and any note text you have consented to index may be processed by Groq and Google (Gemini), which act as our AI subprocessors.
- Daily usage limits apply (Text, Image and Audio queries).
- AI responses may contain errors; always verify with official course materials.
- Do not use the AI to generate prohibited or offensive content.
- You can withdraw AI consent for any note at any time. Withdrawing consent deletes the extracted text used for AI search.

5. Device Documents (Local Docs)
- The app can connect to your device storage (with your explicit, one-time permission) to find and open your own documents.
- Documents you open from device storage are read and edited on your device, and are not uploaded to Foluma's cloud unless you explicitly choose to share them.
- "Share to library" uploads a document you selected to the shared Foluma library. This is a deliberate, per-file action you confirm before it happens. By sharing, you confirm you own the document and agree to the sharing and cloud-processing notice shown in the app.

6. Privacy & Data Retention
- We keep your profile, notes, chats and AI history only as long as your account is active.
- Account deletion removes your personal data. Shared notes you uploaded may be retained for the student community if other students still rely on them; private notes are removed with your account.
- Telegram backups of shared notes are deleted on a best-effort basis. Telegram only permits bots to delete messages sent within the last 48 hours; older backup messages may remain in the private backup channel until manually removed.
- We do not sell personal data to third parties.

7. Restrictions
- No harassment, spam, or unauthorized "scraping" of notes.
- Do not attempt to bypass security, storage, or AI limits.

8. Termination
Foluma reserves the right to suspend accounts that violate these terms.

9. Limitation of Liability
AI-assisted content is for guidance only and does not replace official course materials or qualifications.

10. Contact
Questions about these Terms: ryanmuhia22@gmail.com
""";

  static const String privacyPolicy = """
Foluma Privacy Policy
Effective Date: November 6, 2026

1. Data We Collect
- Profile Data: Name, Email, School, Programme, Academic Year, Semester, and Role.
- Content Data: Notes, PDFs, extracted note text, and chat messages.
- AI Usage Data: Metadata about your AI queries to manage daily limits.
- Consent Data: A record of when you shared a note or allowed/withdrew AI access, so we can prove and honour your choices.

2. How We Use Data
- To provide academic resource sharing and real-time messaging.
- To sync your notes across devices via Supabase.
- To personalise your dashboard based on your programme, stage and academic period.
- To answer questions from notes you have explicitly allowed Foluma AI to index.

3. Where Your Data Is Stored
- Supabase: database, authentication, and small storage objects.
- Cloudflare R2: primary private storage for note files.
- Telegram: backup copy of shared note files only. Private notes are never copied to Telegram.
- Cloudinary: overflow storage used automatically if R2 is unavailable or full.
- Netlify: website hosting and password-reset/email-confirmation pages.
- Groq and Google (Gemini): AI subprocessors that process AI queries and note text you have consented to index.

Private notes are visible only to their owner (and platform administrators for safety and support). Shared notes are visible to students in the same programme across all stages and periods, and to lecturers assigned to the relevant units.

4. AI Consent
- Shared notes are not indexed for AI until the uploader confirms the sharing and AI notice, or the note owner explicitly enables AI access.
- Private notes are not indexed for AI by default. The owner can enable or withdraw AI access per note.
- Withdrawing AI consent deletes the extracted text used for AI search and records the change in our consent log.
- Foluma AI is online-only and depends on Groq and Google Gemini; it is not an on-device model.

5. Security
We use industry-standard encryption in transit (via Supabase and Cloudflare) and private cloud buckets. Note files are served through short-lived signed links or an authenticated proxy; the R2 bucket is not public.

6. Device Documents (Local Docs)
- With your explicit permission, the app may scan your device for documents (PDF, Word, PowerPoint, Excel, text files). Photos and media are never read.
- Documents you open from device storage are processed on your device and are not uploaded or shared unless you take a specific action to do so.
- You can revoke device access at any time in your device settings.

7. Your Choices
- You can update your profile information in the app.
- You can withdraw AI consent for any note at any time.
- You can request account deletion by contacting support. Private notes are deleted with your account; shared notes may be retained for the student community.
- We do not sell personal data to third parties.

8. Updates
We may update this policy periodically. Continued use of the app implies acceptance of any changes.
""";
}
