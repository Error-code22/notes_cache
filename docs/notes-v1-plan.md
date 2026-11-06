# Foluma Notes v1 — build plan and contract

Status: in progress (2026-11-06)
Owner: Ryan / Foluma
Repo: `C:\src\notes_cache` (branch `main`)

## Goal

Rebuild notes around JOOUST's real hierarchy:

```
School (SIIS)
  └── Programme / course (I231 — BSc ICT)
        └── Unit (IGB3405 — IT and Society)
              └── Offering (Stage Y4S1 + Academic period SEM 1 26/27)
                    └── Notes / donations
```

Keep the Android/web app shipping. Do not change the Android package, signing key,
GitHub repo, APK asset names, or support email.

## Locked decisions

### Storage

| Tier | Role | Rules |
|---|---|---|
| Cloudflare R2 | Primary / hot | Notes, documents, audio, previews. Private bucket. Signed URLs. |
| Telegram | Backup / cold | Worker copies every shared asset in <=19 MB chunks. Private notes are **not** copied. |
| Cloudinary | Overflow | Only when R2 upload fills/fails. Documents only. Never the primary path. |

Upload once from the device. The worker copies to Telegram. Serve R2 first, then
Telegram, then Cloudinary. Because the Telegram Bot API can only delete messages
younger than 48 hours, private notes never enter the Telegram backup.

### Visibility and consent

| State | Who reads | Storage | AI | Default |
|---|---|---|---|---|
| Private | Owner only | R2 private prefix | Off | Personal notes |
| Private + AI | Owner only | R2 + owner-tagged chunks | On, owner-scoped | Explicit per-note opt-in |
| Shared | Programme cohort, all stages/periods | R2 + Telegram | Indexed | Donations, rep/lecturer uploads |

- Students may create private notes, but may only publish shared notes by donating.
- Class reps publish for their assigned programme + stage.
- Lecturers publish/read for the units they teach.
- Admins do everything.
- Private notes are never returned by cohort search. `search_chunks_fts` must
  scope private chunks to `owner_id = viewer` and shared chunks to the viewer's
  programme / taught units.
- AI consent is an explicit RPC (`set_note_ai_consent`), logged in `consent_events`.
  Withdrawing consent deletes the note's chunks immediately.
- Privacy copy must never say "local" or "on-device". The AI is cloud-hosted
  (Groq / Google Gemini). The policy must name R2, Telegram and the AI providers.

### RLS

- `notes` select: owner, admin/moderator, same-programme shared notes (all
  stages), lecturer assigned to the unit.
- `notes` insert: private own notes allowed; shared notes only for admins,
  class reps and lecturers via `can_manage_programme_unit`.
- `donated_notes` insert: requires `share_consent_at`, programme, unit,
  programme_unit and unit_code. Students/guests can donate; approval publishes.
- `chunks` select mirrors note access, plus `ai_indexed = true` for non-owners.
- `assets`, `asset_replicas`, `storage_jobs`: service-role only (no client policies).
- `consent_events`: owner/admin read; writes only through definer RPCs.

## Database contract

Migration: `supabase/migrations/20261106000000_taxonomy_storage_consent.sql`
Seed: `supabase/migrations/20261106010000_jooust_seed.sql`

New tables:

- `schools (id, code, name)`
- `programmes (id, school_id, code, name, level, is_active)`
- `academic_periods (id, code, label, academic_year, semester, starts_on, ends_on, is_current)`
- `units (id, code, title, department, is_active)`
- `programme_units (id, programme_id, unit_id, stage_year, stage_semester, is_core, is_provisional)`
- `unit_lecturers (user_id, programme_unit_id)`
- `class_rep_assignments (user_id, programme_id, stage_year, stage_semester, academic_period_id)`
- `assets (id, owner_id, note_id, donation_id, kind, mime_type, file_name, size_bytes, sha256, status, telegram_backup)`
- `asset_replicas (asset_id, provider, bucket, object_key, file_id, message_id, chunk_index, chunk_count, size_bytes, is_primary, last_accessed_at)`
- `storage_jobs (asset_id, type, status, attempts, run_after, locked_at, last_error, payload)`
- `consent_events (user_id, note_id, donation_id, action, policy_version, metadata)`

New columns:

- `profiles`: `school_id`, `programme_id`, `stage_semester`, `current_period_id`
- `notes`: `programme_id`, `unit_id`, `unit_code`, `programme_unit_id`,
  `academic_period_id`, `stage_year`, `stage_semester`, `visibility`,
  `ai_indexed`, `ai_consent_at`, `shared_at`, `consent_version`, `asset_id`
- `donated_notes`: same taxonomy/consent fields, `asset_id`
- `chunks`: `owner_id`, `visibility`, `programme_id`
- `class_schedules`: `programme_id`, `unit_id`, `programme_unit_id`, `academic_period_id`

RPCs added:

- `set_note_ai_consent(note_id, enabled)`
- `set_note_visibility(note_id, shared)`
- `publish_donation(donation_id)` (updated to copy taxonomy/consent)
- `search_chunks_fts(query, limit, user_id)` (rewritten to programme/owner scope)

## Flutter contract

`TaxonomyService` (`lib/taxonomy_service.dart`):

```dart
class School { final String id, code, name; }
class Programme { final String id, schoolId, code, name, level; }
class AcademicPeriod { final String id, code, label; final bool isCurrent; }
class ProgrammeUnit {
  final String id, programmeId, unitId, unitCode, unitTitle;
  final int stageYear, stageSemester;
  final bool isCore, isProvisional;
}

Future<List<School>> getSchools();
Future<List<Programme>> getProgrammes(String schoolId);
Future<List<AcademicPeriod>> getPeriods();
Future<AcademicPeriod?> getCurrentPeriod();
Future<List<ProgrammeUnit>> getProgrammeUnits(
  String programmeId, {
  int? stageYear,
  int? stageSemester,
});
Future<ProgrammeUnit?> getProgrammeUnit(String id);
```

`NoteService` additions/changes:

```dart
Future<List<Note>> getNotesForUser(
  UserProfile u, {
  int? semester,
  String? searchQuery,
  bool myNotesOnly = false,
  String? programmeId,
  String? unitId,
  int? stageYear,
  int? stageSemester,
  String? academicPeriodId,
});
Future<String?> createNote({... taxonomy fields ...});
Future<bool> saveDonatedNote({... taxonomy + consent fields ...});
Future<bool> setNoteAiConsent(String noteId, bool enabled);
Future<bool> setNoteVisibility(String noteId, bool shared);
```

`Note` model additions: `programmeId`, `unitId`, `unitCode`, `stageYear`,
`stageSemester`, `academicPeriodId`, `visibility`, `aiIndexed`, `assetId`.
`UserProfile` additions: `schoolId`, `programmeId`, `stageSemester`,
`currentPeriodId`.

`AuthService.signUp` accepts `schoolId`, `programmeId`, `stageSemester`,
`currentPeriodId` and sends them in auth metadata. The profile page shows
school/programme/stage/period read-only for students (the DB trigger rejects
self-service changes); admins can change them.

`NoteStorageService` (`lib/note_storage_service.dart`):

```dart
Future<StoredAsset?> uploadFile({
  required File file,
  required String userId,
  String? noteId,
  String? donationId,
  bool telegramBackup = true,
  void Function(double)? onProgress,
});
Future<String?> getFileUrl(String noteId);
```

`uploadFile` calls the `note-upload` Edge Function (multipart, R2 primary,
Cloudinary fallback). `getFileUrl` calls `note-file` and returns a signed R2 URL
or a Telegram fallback URL. Legacy `CloudinaryService` stays for old notes.

## Edge function contract

- `note-upload` (authenticated): multipart `file` + fields `note_id` or
  `donation_id`, `kind`, `telegram_backup`, `sha256`. Verifies the caller can
  write the note/donation. Uploads to R2 private bucket. On R2 failure, falls
  back to Cloudinary. Creates `assets` row + `storage_jobs(backup)` when
  `telegram_backup=true`. Returns `{asset_id, provider, key, url, size}`.
- `note-file` (authenticated): body `{note_id}` or `{asset_id}`. Uses the caller's
  JWT to enforce RLS (user-scoped Supabase client). Returns `{url}` signed R2
  URL, `{provider:"r2", proxy:true, download_url}` when only the Cloudflare API
  token is configured, or `{provider:"telegram", chunks:[...], download_url}`
  fallback. The client downloads and concatenates chunks in order.
- `storage-worker` (service role / cron): claims one queued job, downloads the
  R2 object in <=19 MB ranges, sends each chunk to the Telegram channel, writes
  `asset_replicas`, marks the asset `backed_up`. Also processes `delete` jobs.
- `notesy`: no signature change; it already calls `search_chunks_fts`.
- `cloudinary-upload`: add `skip_telegram` flag so overflow uploads do not
  double-back-up.

## File ownership (avoid collisions)

| Area | Files | Owner |
|---|---|---|
| Schema | `supabase/migrations/20261106000000_*`, `20261106010000_*` | lead |
| Seed/importer | seed migration, `supabase/functions/admin-import-units/*` | seed agent |
| Flutter data | `lib/models.dart`, `lib/services.dart`, `lib/login_page.dart`, `lib/profile_page.dart`, `lib/taxonomy_service.dart` | data agent |
| Flutter UI | `lib/upload_note_page.dart`, `lib/donate_notes_page.dart`, `lib/note_detail_page.dart`, `lib/widgets/unit_picker.dart` | UI agent |
| Storage | `supabase/functions/note-upload/*`, `note-file/*`, `storage-worker/*`, `cloudinary-upload/index.ts` | storage agent |
| Admin cloud | `lib/admin_dashboard_page.dart`, `supabase/functions/cloudinary-usage/*`, `r2-usage/*` | admin agent |
| Verification | no production files; adds `docs/notes-v1-verification.md` | verify agent |

## Build waves

1. Schema + seed (done, pending review).
2. Parallel: Flutter data, Flutter UI, storage functions, admin cloud status.
3. Verification: `flutter analyze`, SQL review, RLS matrix, function smoke tests.
4. Apply migration to Supabase, deploy functions, set secrets, run a real
   upload/download/backup test.
5. Ship v1.0.7.

## Status (2026-11-06)

- Applied to production: `20261106000000`, `20261106010000`, `20261106020000`,
  `20261106030000` (legacy/Google profile onboarding), `20261106040000`
  (INSERT ... RETURNING SELECT policy).
- Deployed: `note-upload`, `note-file`, `storage-worker`, `cloudinary-upload`.
- Secrets present: `R2_ACCOUNT_ID`, `R2_NOTES_BUCKET=foluma-notes`,
  `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`, `TELEGRAM_BOT_TOKEN`,
  `TELEGRAM_CHANNEL_ID`, `STORAGE_WORKER_SECRET`.
- R2 is primary via the Cloudflare REST API (S3 keys are not set). The private
  bucket is created on first upload. `note-upload` also falls back to Cloudinary
  if R2 is unavailable.
- Real E2E passed: R2 upload → authenticated R2 proxy download (hash match) →
  worker backup from R2 to Telegram → Telegram chunk fallback (hash match) →
  cleanup through a delete job.
- RLS matrix passed: same-programme shared reads, cross-programme denial,
  owner-only private notes, lecturer/class-rep shared uploads, student shared
  upload denial, donation consent requirement, per-note AI consent and denial
  for other users.
- Admin Cloud Status verified live: Supabase `admin_cloud_stats`,
  `cloudinary-usage`, and `r2-usage` (bucket-list source with timestamps).

## Open follow-ups

- Admin CSV importer for official basket lists (all years).
- Full video recordings (parked). Audio-first when it returns.
- Notifications end-to-end still unverified.
- Legacy notes (71) intentionally remain owner/staff-only until an admin
  assigns a programme/unit and re-uploads or re-files them.
