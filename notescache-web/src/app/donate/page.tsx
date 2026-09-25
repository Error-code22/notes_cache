'use client'

import { useEffect, useState } from 'react'
import { useAuth, supabase } from '../../lib/auth'
import { categoryFromName } from '../../lib/utils'
import { pptxFileToPdf, type ConvertProgress } from '../../lib/pptx-to-pdf'
import AppShell from '../../components/AppShell'
import ConvertOverlay from '../../components/ConvertOverlay'

type LibraryNote = {
  id: string
  title: string
  lecturer_name?: string
  target_year?: number
  semester?: number
  gdrive_id?: string
  category?: string
  content?: string
  file_size?: number
  created_at?: string
  user_id?: string
}

// A row in `donated_notes` (review queue). id is BIGSERIAL.
type DonationNote = {
  id: number
  title: string
  lecturer_name?: string
  target_year?: number
  semester?: number
  gdrive_id?: string
  file_url?: string
  category?: string
  content?: string
  file_size?: number
  created_at?: string
  user_id?: string
  status?: string
  library_note_id?: string | null
}

// Merged browse item: either a donation or a library note.
// linkId is what /note?id=... should open (approved donations link to their
// library copy in `notes`, never to the donation row itself).
type BrowseRow = Omit<LibraryNote, 'id'> & {
  id: string | number
  linkId: string
  library_note_id?: string | null
}

export default function DonatePage() {
  const { user, profile } = useAuth()
  const [tab, setTab] = useState<'donate' | 'browse'>('donate')
  const [files, setFiles] = useState<File[]>([])
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [year, setYear] = useState<number | null>(null)
  const [semester, setSemester] = useState(1)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState('')
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)
  const [convert, setConvert] = useState<{ label: string; detail?: string; percent?: number } | null>(null)
  const [lastTitles, setLastTitles] = useState<string[]>([])
  const [list, setList] = useState<BrowseRow[]>([])
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')

  // Default year to the signed-in student's year so the library filter shows it
  useEffect(() => {
    if (profile?.year_level) setYear(profile.year_level)
    else if (year == null) setYear(1)
  }, [profile?.year_level]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 350)
    return () => clearTimeout(t)
  }, [search])

  useEffect(() => {
    ;(async () => {
      // Browse = approved donations (donated_notes) + student uploads already
      // in the shared library (notes). Both are filtered by search first.
      const term = debounced.trim() ? `%${debounced.trim()}%` : null

      let dq = supabase
        .from('donated_notes')
        .select('id, title, lecturer_name, target_year, semester, gdrive_id, file_url, category, content, file_size, created_at, user_id, library_note_id')
        .eq('status', 'approved')
        .order('created_at', { ascending: false })
        .limit(100)
      if (term) dq = dq.ilike('title', term)

      let lq = supabase
        .from('notes')
        .select('id, title, lecturer_name, target_year, semester, gdrive_id, category, content, file_size, created_at, user_id')
        .in('lecturer_name', ['Student Donation', 'Student Upload'])
        .order('created_at', { ascending: false })
        .limit(100)
      if (term) lq = lq.ilike('title', term)

      const [dn, ln] = await Promise.all([dq, lq])
      if (dn.error) console.error('donate browse (donations)', dn.error.message)
      if (ln.error) console.error('donate browse (library)', ln.error.message)

      const donations: BrowseRow[] = ((dn.data as DonationNote[]) || []).map((d) => ({
        ...d,
        linkId: d.library_note_id ?? String(d.id),
      }))
      const library: BrowseRow[] = ((ln.data as LibraryNote[]) || []).map((n) => ({
        ...n,
        linkId: n.id,
      }))

      let rows = [...donations, ...library]
        .sort((a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime())
        .slice(0, 100)

      // Prefer showing the signed-in user's own uploads first if list is empty after filter
      if (rows.length === 0 && user) {
        let mq = supabase
          .from('notes')
          .select('id, title, lecturer_name, target_year, semester, gdrive_id, category, content, file_size, created_at, user_id')
          .eq('user_id', user.id)
          .order('created_at', { ascending: false })
          .limit(50)
        if (term) mq = mq.ilike('title', term)
        const { data: mine } = await mq
        rows = ((mine as LibraryNote[]) || []).map((n) => ({ ...n, linkId: n.id }))
      }
      setList(rows)
    })()
  }, [debounced, done])

  function onPick(listIn: FileList | null) {
    if (!listIn) return
    const allowed = /\.(pdf|docx?|pptx?|xlsx?|csv|jpg|jpeg|png|txt|md)$/i
    const next = Array.from(listIn).filter((f) => allowed.test(f.name))
    setFiles((prev) => [...prev, ...next].slice(0, 10))
    if (!title && next[0]) setTitle(next[0].name)
  }

  async function uploadToCloudinary(file: File | Blob, filename: string, token: string, userId: string) {
    const fd = new FormData()
    fd.append('file', file, filename)
    fd.append('folder', 'donations')
    fd.append('userId', userId)
    const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/cloudinary-upload`, {
      method: 'POST',
      headers: {
        apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        Authorization: `Bearer ${token}`,
      },
      body: fd,
    })
    const data = await res.json().catch(() => ({} as Record<string, unknown>))
    if (!res.ok || data.success !== true) {
      throw new Error(String(data.error || data.message || `Upload failed (HTTP ${res.status})`))
    }
    if (!data.url) throw new Error('Upload succeeded but no file URL was returned.')
    return data as { url: string; telegramMsgId?: number; telegramFileId?: string }
  }

  async function donate() {
    setError('')
    if (!files.length) {
      setError('Select at least one file.')
      return
    }
    if (!user) {
      setError('Sign in so your donation can be submitted for review.')
      return
    }
    setBusy(true)
    const session = await supabase.auth.getSession()
    const token = session.data.session?.access_token
    if (!token) {
      setBusy(false)
      setError('Session expired. Sign in again.')
      return
    }

    let ok = 0
    const savedTitles: string[] = []
    const targetYear = year ?? profile?.year_level ?? 1

    for (let i = 0; i < files.length; i++) {
      const file = files[i]
      try {
        const noteTitle = files.length === 1 && title.trim() ? title.trim() : file.name
        const isPptx = /\.(pptx|ppsx)$/i.test(file.name)

        // 1) Upload original
        setProgress(isPptx
          ? `Uploading ${i + 1}/${files.length}… (then converting slides to PDF)`
          : `Uploading ${i + 1}/${files.length}…`)
        const original = await uploadToCloudinary(file, file.name, token, user.id)

        // 2) For PPTX: build PDF in this browser and upload it too
        let pdfUrl: string | null = null
        if (isPptx) {
          setProgress('')
          setConvert({ label: `Converting ${file.name}…`, detail: 'Unpacking slides', percent: 30 })
          try {
            const pdfBlob = await pptxFileToPdf(file, noteTitle, (p: ConvertProgress) => {
              if (p.phase === 'render') {
                const pct = 35 + Math.round((p.current / Math.max(p.total, 1)) * 50)
                setConvert({
                  label: `Converting ${file.name}…`,
                  detail: `Slide ${p.current} of ${p.total}`,
                  percent: pct,
                })
              }
            })
            const pdfName = file.name.replace(/\.(pptx|ppsx)$/i, '') + '.pdf'
            setConvert({ label: 'Uploading PDF…', detail: pdfName, percent: 92 })
            const pdfUpload = await uploadToCloudinary(pdfBlob, pdfName, token, user.id)
            pdfUrl = pdfUpload.url
            setConvert(null)
          } catch (convErr) {
            console.error('pptx→pdf', convErr)
            setConvert(null)
          }
        }

        // 3) Insert into the review queue: gdrive_id = original, pdf_url = converted
        const row: Record<string, unknown> = {
          title: noteTitle,
          lecturer_name: 'Student Donation',
          target_year: targetYear,
          semester,
          gdrive_id: original.url,
          file_url: original.url,
          content: description.trim(),
          category: categoryFromName(file.name),
          file_size: file.size,
          user_id: user.id,
          status: 'pending',
          ...(original.telegramMsgId != null ? { telegram_msg_id: original.telegramMsgId } : {}),
          ...(original.telegramFileId != null ? { telegram_file_id: original.telegramFileId } : {}),
          ...(pdfUrl ? { pdf_url: pdfUrl } : {}),
        }

        const { data: inserted, error: dbErr } = await supabase.from('donated_notes').insert(row).select('id').single()
        if (dbErr) throw new Error(`File uploaded but submission failed: ${dbErr.message}`)
        if (!inserted) throw new Error('Submission returned no row.')

        savedTitles.push(noteTitle)
        ok++
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Upload failed')
        break
      }
    }

    setBusy(false)
    setProgress('')
    if (ok > 0) {
      setDone(true)
      setLastTitles(savedTitles)
      setFiles([])
      setTitle('')
      setDescription('')
    }
  }

  return (
    <AppShell title="Donate Notes">
      <ConvertOverlay
        open={!!convert || (!!progress && busy)}
        label={convert?.label || progress || 'Uploading…'}
        detail={convert?.detail}
        percent={convert?.percent ?? (progress && !convert ? undefined : convert?.percent)}
      />
      <div className="flex gap-2 mb-5">
        <button
          onClick={() => setTab('donate')}
          className={`flex-1 py-2 rounded-xl text-xs font-bold ${tab === 'donate' ? 'bg-pink-600 text-white' : 'bg-white dark:bg-[#1C1C1E] text-gray-500 border border-gray-200 dark:border-white/10'}`}
        >
          DONATE
        </button>
        <button
          onClick={() => setTab('browse')}
          className={`flex-1 py-2 rounded-xl text-xs font-bold ${tab === 'browse' ? 'bg-pink-600 text-white' : 'bg-white dark:bg-[#1C1C1E] text-gray-500 border border-gray-200 dark:border-white/10'}`}
        >
          BROWSE
        </button>
      </div>

      {tab === 'donate' ? (
        <>
          <div className="bg-pink-50 dark:bg-pink-500/10 border border-pink-200 dark:border-pink-500/30 rounded-xl px-4 py-3 text-[13px] text-pink-800 dark:text-pink-200 mb-5">
            Share notes with everyone in the shared library. Submissions are
            reviewed by an admin before they are published. Sign-in required.
            {!user && (
              <> <a href="/login" className="font-bold underline">Sign in</a> to donate.</>
            )}
          </div>

          {files.length === 0 ? (
            <div className="text-center py-12 bg-white dark:bg-[#1C1C1E] border border-dashed border-gray-300 dark:border-white/15 rounded-2xl">
              <p className="text-sm text-gray-500 mb-4">PDF, DOC, PPT, Excel, images, text…</p>
              <label className="inline-block px-5 py-3 bg-pink-600 text-white rounded-xl text-sm font-bold cursor-pointer">
                Select Files
                <input
                  type="file"
                  multiple
                  accept=".pdf,.doc,.docx,.ppt,.pptx,.xls,.xlsx,.csv,.jpg,.jpeg,.png,.txt,.md"
                  className="hidden"
                  onChange={(e) => onPick(e.target.files)}
                />
              </label>
            </div>
          ) : (
            <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-5 space-y-4">
              <div>
                <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Title</label>
                <input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  placeholder="e.g. Thermodynamics Lecture 4.pdf"
                  className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
                />
              </div>
              <div>
                <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Description</label>
                <input
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
                />
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Year</label>
                  <select
                    value={year ?? 1}
                    onChange={(e) => setYear(Number(e.target.value))}
                    className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
                  >
                    {[1, 2, 3, 4].map((y) => (
                      <option key={y} value={y}>Year {y}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Semester</label>
                  <select
                    value={semester}
                    onChange={(e) => setSemester(Number(e.target.value))}
                    className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
                  >
                    <option value={1}>Semester 1</option>
                    <option value={2}>Semester 2</option>
                  </select>
                </div>
              </div>
              <ul className="text-xs text-gray-500 space-y-1">
                {files.map((f, i) => (
                  <li key={i} className="flex justify-between gap-2">
                    <span className="truncate">{f.name}</span>
                    <button onClick={() => setFiles((p) => p.filter((_, j) => j !== i))} className="text-red-500 shrink-0">
                      remove
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          )}

          {error && <p className="text-sm text-red-600 mt-3">{error}</p>}
          {progress && <p className="text-sm text-indigo-600 mt-3">{progress}</p>}
          {done && (
            <div className="mt-3 rounded-xl bg-emerald-50 dark:bg-emerald-500/10 border border-emerald-200 dark:border-emerald-500/30 px-4 py-3 text-sm text-emerald-800 dark:text-emerald-200">
              <p className="font-semibold mb-1">Submitted for review.</p>
              <p className="text-xs mb-2">An admin will publish them to the shared library.</p>
              {lastTitles.length > 0 && (
                <ul className="text-xs mb-2 list-disc pl-4">
                  {lastTitles.map((t) => <li key={t}>{t}</li>)}
                </ul>
              )}
              <a href="/notes?mine=1" className="font-bold underline">View in My Notes</a>
              {' · '}
              <a href="/notes" className="font-bold underline">Academic Notes</a>
            </div>
          )}

          {files.length > 0 && (
            <button
              onClick={donate}
              disabled={busy || !user}
              className="w-full mt-4 py-3 bg-pink-600 text-white rounded-xl text-sm font-bold disabled:opacity-50"
            >
              {busy ? 'Uploading…' : !user ? 'Sign in to donate' : `DONATE ${files.length} FILE(S)`}
            </button>
          )}
        </>
      ) : (
        <>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search donations…"
            className="w-full mb-4 px-4 py-2 rounded-full border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white"
          />
          <div className="space-y-2">
            {list.map((n) => (
              <a
                key={`${n.linkId}-${n.id}`}
                href={`/note?id=${n.linkId}`}
                className="block bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 hover:border-pink-300 transition"
              >
                <div className="font-semibold text-gray-900 dark:text-white text-sm">{n.title}</div>
                <div className="text-xs text-gray-500 mt-1">
                  Year {n.target_year ?? '—'} · Sem {n.semester ?? '—'} · {n.category || 'file'} ·{' '}
                  {n.lecturer_name || 'Student'}
                </div>
              </a>
            ))}
            {list.length === 0 && (
              <div className="text-center py-12 text-gray-400 text-sm">
                No donations in the library yet.
                <div className="mt-2">
                  <a href="/notes" className="text-indigo-600 font-medium underline">Open Academic Notes</a>
                </div>
              </div>
            )}
          </div>
        </>
      )}
    </AppShell>
  )
}
