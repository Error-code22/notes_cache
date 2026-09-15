'use client'

import { Suspense, useEffect, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useAuth, supabase } from '../../lib/auth'
import { hasStaffVisibility, noteType, TYPE_META, viewUrl, isSlideExt, extFromName } from '../../lib/utils'
import { pptxFileToPdf, pdfViewerUrl, type ConvertProgress } from '../../lib/pptx-to-pdf'
import AppShell from '../../components/AppShell'
import ConvertOverlay from '../../components/ConvertOverlay'

type Note = {
  id: string
  title: string
  lecturer_name?: string
  target_year?: number
  semester?: number
  gdrive_id?: string
  category?: string
  content?: string
  user_id?: string
  created_at?: string
  summary?: string | null
  file_size?: number
  pdf_url?: string | null
}

function NoteDetail() {
  const params = useSearchParams()
  const id = params.get('id') || ''
  const { user, profile } = useAuth()
  const [note, setNote] = useState<Note | null>(null)
  const [loading, setLoading] = useState(true)
  const [summary, setSummary] = useState('')
  const [sumBusy, setSumBusy] = useState(false)
  const [openBusy, setOpenBusy] = useState(false)
  const [convert, setConvert] = useState<{ label: string; detail?: string; percent?: number } | null>(null)
  const [msg, setMsg] = useState('')
  const isGuest = !user
  const isAdmin = String(profile?.role || '').toLowerCase().includes('admin')

  useEffect(() => {
    if (!id) { setLoading(false); return }
    ;(async () => {
      const { data } = await supabase.from('notes').select('*').eq('id', id).maybeSingle()
      setNote(data as Note | null)
      setSummary(data?.summary || '')
      setLoading(false)
    })()
  }, [id])

  async function generateSummary() {
    if (!note || isGuest) return
    setSumBusy(true)
    setMsg('')
    try {
      const session = await supabase.auth.getSession()
      const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.data.session?.access_token}`,
        },
        body: JSON.stringify({
          action: 'summarize',
          title: note.title,
          content: note.content || note.title,
          userId: user?.id,
        }),
      })
      const data = await res.json()
      const text = data?.content || ''
      setSummary(text)
      if (text) await supabase.from('notes').update({ summary: text }).eq('id', note.id)
      else setMsg('Could not generate a summary for this note.')
    } catch {
      setMsg('Summary failed. Try again.')
    } finally {
      setSumBusy(false)
    }
  }

  async function openNote() {
    if (isGuest) { window.location.href = '/login'; return }
    if (!note?.gdrive_id) { setMsg('File URL missing.'); return }

    try {
      await supabase.rpc('log_download', { p_note_id: note.id, p_file_size: note.file_size || 0 })
    } catch { /* optional */ }

    const ext = extFromName(note.title || '') ||
      (String(note.category || '').toLowerCase() === 'slides' ? 'pptx' : '')

    // Slides: web/in-app use the PDF twin. External/system open stays on the original PPTX.
    if (isSlideExt(ext)) {
      if (note.pdf_url) {
        window.open(`/view?url=${encodeURIComponent(note.pdf_url)}&ext=pdf`, '_blank')
        return
      }

      // Older note without pdf_url — convert in this browser (no server) and save
      setOpenBusy(true)
      setConvert({ label: 'Preparing PDF from slides…', detail: 'Downloading presentation', percent: 5 })
      try {
        const res = await fetch(note.gdrive_id!)
        if (!res.ok) throw new Error(`HTTP ${res.status}`)
        const blob = await res.blob()
        setConvert({ label: 'Preparing PDF from slides…', detail: 'Reading slide content', percent: 20 })

        const onProgress = (p: ConvertProgress) => {
          if (p.phase === 'parse') {
            setConvert({ label: 'Preparing PDF from slides…', detail: 'Unpacking slides', percent: 25 })
          } else if (p.phase === 'render') {
            const pct = 30 + Math.round((p.current / Math.max(p.total, 1)) * 55)
            setConvert({
              label: 'Building PDF…',
              detail: `Slide ${p.current} of ${p.total}`,
              percent: pct,
            })
          } else {
            setConvert({ label: 'Finishing…', detail: 'Packaging PDF', percent: 90 })
          }
        }

        const pdfBlob = await pptxFileToPdf(
          new File([blob], note.title || 'slides.pptx', {
            type: blob.type || 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
          }),
          note.title,
          onProgress,
        )
        const pdfUrl = URL.createObjectURL(new Blob([pdfBlob], { type: 'application/pdf' }))

        setConvert({ label: 'Saving PDF…', detail: 'Uploading for next time', percent: 95 })
        try {
          const session = await supabase.auth.getSession()
          const token = session.data.session?.access_token
          if (token) {
            const fd = new FormData()
            fd.append('file', pdfBlob, (note.title || 'slides').replace(/\.(pptx?|ppsx?)$/i, '') + '.pdf')
            fd.append('folder', 'donations')
            fd.append('userId', user?.id || 'guest')
            const up = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/cloudinary-upload`, {
              method: 'POST',
              headers: {
                apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
                Authorization: `Bearer ${token}`,
              },
              body: fd,
            })
            const upData = await up.json().catch(() => ({}))
            if (up.ok && upData?.url) {
              await supabase.from('notes').update({ pdf_url: upData.url }).eq('id', note.id)
              setNote({ ...note, pdf_url: upData.url })
            }
          }
        } catch { /* still show local PDF */ }

        setConvert(null)
        setMsg('')
        window.open(pdfViewerUrl(pdfUrl), '_blank')
      } catch {
        setConvert(null)
        setMsg('Could not build PDF — opening slide preview instead.')
        window.open(viewUrl(note), '_blank')
      } finally {
        setOpenBusy(false)
      }
      return
    }

    window.open(viewUrl(note), '_blank')
  }

  async function removeNote() {
    if (!note || !isAdmin) return
    if (!window.confirm('Delete this note permanently?')) return
    await supabase.from('notes').delete().eq('id', note.id)
    window.location.href = '/notes'
  }

  if (loading) return <AppShell title="Note"><div className="text-center py-16 text-gray-400">Loading…</div></AppShell>
  if (!note) return <AppShell title="Note"><div className="text-center py-16 text-gray-500">Note not found.</div></AppShell>

  const t = noteType(note.title, note.category)
  const meta = TYPE_META[t]

  return (
    <AppShell title="Note details" wide
      action={isAdmin ? (
        <button onClick={removeNote} className="text-xs font-bold px-3 py-1.5 rounded-full bg-red-600 text-white shrink-0">DELETE</button>
      ) : undefined}
    >
      <ConvertOverlay
        open={!!convert}
        label={convert?.label || ''}
        detail={convert?.detail}
        percent={convert?.percent}
      />
      <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-3xl p-6">
        <div className="flex flex-wrap items-center gap-2 mb-3">
          <span className="px-2 py-0.5 rounded-md text-[10px] font-bold text-white" style={{ backgroundColor: meta.color }}>{meta.label}</span>
          <span className="text-[12px] text-gray-500">Year {note.target_year ?? '—'}</span>
          {note.semester ? <span className="text-[12px] text-gray-500">Semester {note.semester}</span> : null}
          {note.created_at ? (
            <span className="text-[12px] text-gray-400">{new Date(note.created_at).toLocaleDateString()}</span>
          ) : null}
        </div>
        <h1 className="text-xl font-bold text-gray-900 dark:text-white mb-1">{note.title}</h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">{note.lecturer_name || 'Unknown lecturer'}</p>
        {note.content ? (
          <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap mb-4">{note.content.slice(0, 1500)}{note.content.length > 1500 ? '…' : ''}</p>
        ) : null}

        <div className="flex flex-wrap gap-2 mb-5">
          <button
            onClick={openNote}
            disabled={openBusy}
            className="px-5 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50"
          >
            {openBusy ? 'Preparing…' : 'OPEN & READ NOTE'}
          </button>
          {!isGuest && (
            <button
              onClick={generateSummary}
              disabled={sumBusy}
              className="px-5 py-3 border border-violet-500 text-violet-600 dark:text-violet-400 rounded-xl text-sm font-bold hover:bg-violet-50 dark:hover:bg-violet-500/10 transition disabled:opacity-50"
            >
              {sumBusy ? 'Generating…' : summary ? 'Regenerate AI Summary' : 'AI Summary'}
            </button>
          )}
        </div>
        {msg && <p className="text-sm text-amber-600 mb-3">{msg}</p>}
        {isGuest && (
          <p className="text-[13px] text-gray-500 mb-4">
            Sign in to open and read notes. <a href="/login" className="text-indigo-600 font-medium">Sign in</a>
          </p>
        )}

        {summary && (
          <div className="rounded-2xl border border-violet-200 dark:border-violet-500/30 bg-violet-50/50 dark:bg-violet-500/10 p-4">
            <div className="text-[11px] font-bold text-violet-600 dark:text-violet-300 uppercase tracking-wide mb-2">AI Summary</div>
            <div className="text-sm text-gray-800 dark:text-gray-200 whitespace-pre-wrap">{summary}</div>
          </div>
        )}
      </div>
    </AppShell>
  )
}

export default function NoteDetailPage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center text-gray-400">Loading…</div>}>
      <NoteDetail />
    </Suspense>
  )
}
