class AppPolicies {
  static const String termsAndConditions = """
**NotesCache Terms & Conditions**
Effective Date: April 28, 2026

1. Acceptance of Terms
By accessing or using NotesCache, you agree to be bound by these terms. If you are using the app as a student, lecturer, or guest, you must adhere to academic integrity standards.

2. User Accounts
- Users must provide accurate information (Name, Email, Academic Year).
- You are responsible for maintaining the confidentiality of your account.
- Guest accounts have limited functionality and AI usage.

3. Content & Intellectual Property
- You retain ownership of the notes you upload.
- By uploading, you grant NotesCache a license to display and distribute the content to your peers/groups within the app.
- No copyrighted material may be uploaded without the owner's permission.

4. Notesy AI Service
- AI features are provided for academic assistance.
- Daily usage limits apply (Text and Image queries).
- Do not use the AI to generate prohibited or offensive content.

5. Restrictions
- No harassment, spam, or unauthorized "scraping" of notes.
- Do not attempt to bypass security or AI limits.

6. Device Documents (Local Docs)
- The app can connect to your device storage (with your explicit, one-time permission) to find and open your own documents.
- Opened documents are read and edited in place on your device. The app never uploads or copies them unless you explicitly choose to.
- "Share to library" uploads a document you selected to the shared NotesCache library. This is a deliberate, per-file action you confirm before it happens. By sharing, you confirm you own the document and agree to it being visible to other app users.

7. Termination
NotesCache reserves the right to suspend accounts that violate these terms.
""";

  static const String privacyPolicy = """
**NotesCache Privacy Policy**
Effective Date: April 28, 2026

1. Data We Collect
- Profile Data: Name, Email, Academic Year, and Role.
- Content Data: Notes, PDFs, and chat messages.
- AI Usage Data: Metadata about your AI queries to manage daily limits.

2. How We Use Data
- To provide academic resource sharing and real-time messaging.
- To sync your notes across devices via Supabase.
- To personalize your dashboard experience based on your academic year.

3. Third-Party Services
- Supabase: For database and authentication security.
- Google: For font rendering, sign-in, and file metadata detection.
- Netlify: To host password reset and email confirmation pages.

4. Security
We use industry-standard encryption (via Supabase) to protect your data. Your files are stored in secure cloud buckets.

5. Device Documents (Local Docs)
- With your explicit permission, the app may scan your device for documents (PDF, Word, PowerPoint, Excel, text files). Photos and media are never read.
- Documents you open are processed on your device. They are not uploaded, copied, or shared unless you take a specific action to do so.
- You can revoke device access at any time in your device settings.

6. Your Choices
You can update your profile information in the settings or contact support to request account deletion.

7. Updates
We may update this policy periodically. Continued use of the app implies acceptance of any changes.
""";
}
