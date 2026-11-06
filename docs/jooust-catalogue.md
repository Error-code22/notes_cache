# JOOUST catalogue and admin CSV importer

Status: seed + importer written 2026-11-06. **Not applied to the live database.**

The catalogue is the `schools -> programmes -> units -> programme_units` chain
described in `docs/notes-v1-plan.md`. Notes point at a `programme_unit` (the
offering of a unit at a stage/semester), so an admin can correct codes and titles
without touching the library.

## Files

| File | Purpose |
|---|---|
| `supabase/migrations/20261106010000_jooust_seed.sql` | Initial schools, SIIS programmes, 2026/27 semester 1 period, I231 Y4S1 basket, provisional Y1S1 basket. |
| `supabase/functions/admin-import-units/index.ts` | Admin-only CSV importer for `units` + `programme_units`. |

## Seed contents

### Schools

`SAFS`, `SBPMAS`, `SBE`, `SEHSS`, `SSPNRM`, `SIIS`, `SHS`, `SET`.

### SIIS programmes

| Code | Name |
|---|---|
| `I231` | BSc Information Communication Technology |
| `I232` | BSc Computer Security and Forensics |
| `I233` | BSc Business Information Systems |
| `I234` | BSc Library and Information Science |

Programme codes are unique **per school** (`unique (school_id, code)`), so the
seed resolves `I231` by joining `SIIS`, not by code alone. A same-coded programme
in another school can never multiply the basket.

### Academic period

| Code | Label | Academic year | Semester | Current |
|---|---|---|---|---|
| `2026/2027-S1` | `SEM 1 26/27` | `2026/2027` | 1 | yes |

The seed clears any other `is_current` row before inserting this period.

### I231 Year 4 Semester 1 — authoritative 2026/27 basket

These rows are `is_core = true`, `is_provisional = false`:

| Unit code | Unit title |
|---|---|
| `IGB3405` | IT and Society |
| `ITB1399` | Industrial Attachment |
| `ITB1401` | Cyber Law |
| `ITB1403` | Advanced Network Management |
| `ITB1405` | Web Application Technologies |
| `ITB1407` | ICT Policy and Strategic Planning |
| `ITB1409` | Introduction to Knowledge Management |
| `ITB1411` | Innovation Techniques and Models |
| `ITB1413` | Group Design Workshop |

### I231 Year 1 Semester 1 — provisional

These rows are `is_core = true`, `is_provisional = true`. They came from the
JOOUST programme page (older codes); replace them with the current official
basket when it is available.

| Unit code | Unit title |
|---|---|
| `ICT 3111` | Introduction to Computer Systems |
| `ICT 3112` | Linux/Unix Administration |
| `IIT 3112` | Introduction to Programming |
| `IIT 3114` | HTML Programming |
| `SMA 3113` | Logical Functions |
| `SMA 3114` | Analytical Methods for Computing |
| `EEL 3115` | Communication Skills |
| `SBI 3114` | HIV and AIDS |

The seed only writes catalogue rows. It does not update, reassign or delete any
existing note.

## CSV format

The Edge Function accepts JSON:

```json
{
  "programme_id": "<I231 programme UUID>",
  "csv": "stage_year,stage_semester,unit_code,unit_title,is_core\n4,1,ITB1405,Web Application Technologies,true\n",
  "replace_provisional": false
}
```

### Columns

Header row is optional. If present, it must be exactly:

```csv
stage_year,stage_semester,unit_code,unit_title,is_core
```

Data rows use the same five columns in that order:

```csv
stage_year,stage_semester,unit_code,unit_title,is_core
4,1,IGB3405,IT and Society,true
1,1,ICT 3111,Introduction to Computer Systems,true
```

- Quoted values are supported, including commas and escaped quotes (`""`).
- Blank lines are ignored.
- `stage_year` must be an integer 1–6.
- `stage_semester` must be an integer 1–3.
- `unit_code` is required. It is trimmed, internal whitespace is collapsed, and
  it is stored upper-case, so `itb1405` and `ITB  1405` update `ITB1405`.
- `unit_title` is required. Runs of whitespace (including newlines inside quoted
  cells) collapse to one space.
- `is_core` accepts `true/false`, `yes/no`, `y/n`, `1/0` (case-insensitive).
  Blank defaults to `true`.
- Exact duplicate rows (`code + stage_year + stage_semester`) are skipped.
  Duplicate keys with a different title or `is_core` value are rejected.
- Maximum 1,000 data rows and 2,000,000 characters per request.

All rows are validated before the first write. Errors are returned as strings
that begin with the physical CSV line, for example:

```json
{
  "inserted": 0,
  "updated": 0,
  "skipped": 0,
  "deleted": 0,
  "errors": ["Line 4: stage_semester must be an integer between 1 and 3."]
}
```

### What gets written

1. `units` is upserted on `code`; the title is updated and `is_active` is set to
   `true`. Units are never deleted.
2. `programme_units` is upserted on
   `(programme_id, unit_id, stage_year, stage_semester)`. Imported rows become
   `is_provisional = false` and keep the CSV `is_core` value.
3. If `replace_provisional = true`, provisional `programme_units` rows for the
   programme whose unit code is absent from the CSV are candidates for deletion.

The response always contains `inserted`, `updated`, `skipped`, `deleted` and
`errors`:

- `inserted`: CSV rows that created a new programme-unit link.
- `updated`: CSV rows whose existing link changed, or whose unit title/active
  flag changed.
- `skipped`: identical rows and exact duplicate CSV rows.
- `deleted`: provisional links retired (0 unless `replace_provisional = true`).
- `errors`: empty on success; line-tagged strings on HTTP 400.

Validation failures return HTTP 400. A valid JWT without an admin role returns
HTTP 403. Missing/invalid auth returns HTTP 401.

## Replacing provisional Y1S1 rows

1. Get the `I231` programme UUID (in the SIIS school):

   ```sql
   select p.id, p.code, p.name
   from public.programmes p
   join public.schools s on s.id = p.school_id
   where s.code = 'SIIS' and p.code = 'I231';
   ```

2. Export the **complete** current basket for the programme, including every
   stage/year and semester that should stay. If you only send Y1S1, do not set
   `replace_provisional` unless you intend to retire every other provisional
   link too.

3. Call the function with the admin's access token. Never put a service-role key
   in the Flutter app or a browser:

   ```bash
   curl -i \
     -H "Authorization: Bearer <admin-user-jwt>" \
     -H "apikey: <supabase-anon-key>" \
     -H "Content-Type: application/json" \
     -d '{"programme_id":"<I231-uuid>","csv":"stage_year,stage_semester,unit_code,unit_title,is_core\n1,1,ICT 3111,Introduction to Computer Systems,true\n","replace_provisional":true}' \
     "https://<project-ref>.supabase.co/functions/v1/admin-import-units"
   ```

   The function verifies the JWT and then reads the caller's own
   `profiles.role` with a user-scoped client. A `role` in the JSON body is
   ignored.

4. `replace_provisional = true` deletes only `programme_units` rows that:
   - belong to the supplied programme,
   - have `is_provisional = true`,
   - reference a unit code that is **not** anywhere in the CSV,
   - and are not referenced by `notes`, `donated_notes`, `class_schedules` or
     `unit_lecturers`.

   Referenced links are retained. Notes and `units` rows are never deleted.

5. Re-run the same call with `replace_provisional = false` (or omit it) for
   later additions; rows already present are counted as `skipped`.

Example request body (the CSV string is JSON-escaped, so `\n` becomes a real
newline in the parsed value):

```json
{
  "programme_id": "00000000-0000-0000-0000-000000000000",
  "csv": "stage_year,stage_semester,unit_code,unit_title,is_core\n1,1,ICT 3111,Introduction to Computer Systems,true\n1,1,ICT 3112,Linux/Unix Administration,true\n",
  "replace_provisional": true
}
```

## Verification queries

Read-only checks after applying the migration (or in a local database):

```sql
-- I231 basket by stage
select pu.stage_year, pu.stage_semester, u.code, u.title,
       pu.is_core, pu.is_provisional
from public.programme_units pu
join public.programmes p on p.id = pu.programme_id
join public.schools s on s.id = p.school_id
join public.units u on u.id = pu.unit_id
where s.code = 'SIIS' and p.code = 'I231'
order by pu.stage_year, pu.stage_semester, u.code;

-- Provisional rows still waiting for an official basket
select p.code, pu.stage_year, pu.stage_semester, u.code, u.title
from public.programme_units pu
join public.programmes p on p.id = pu.programme_id
join public.units u on u.id = pu.unit_id
where pu.is_provisional = true
order by p.code, pu.stage_year, pu.stage_semester, u.code;
```

## Notes / limitations

- The importer updates the shared `units` catalogue by code. If two programmes
  use the same code with different titles, the last import wins; the CSV itself
  rejects two different titles for one code in a single request.
- The function makes several REST calls, so it is not a single SQL transaction.
  All CSV validation happens first; a mid-import database failure can leave
  earlier upserts committed.
- The seed migration must not be applied live from the seed agent's session;
  applying it is the lead's step after review.
- School/programme names in the seed are transcribed from the URLs named in the
  migration header; they have not been re-checked against a live JOOUST page in
  this review.
