'use client'

import { useEffect, useMemo, useRef, useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
)

const NOTESY_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`

type Note = {
  id: string
  title: string
  lecturer_name?: string
  target_year?: number
  semester?: number
  gdrive_id?: string
  file_size?: number
  category?: string
  created_at?: string
  summary?: string
}

type ChatMsg = { role: 'user' | 'assistant'; content: string }

const GUEST_LIMIT = 3
const storageKey = 'notesy_web_history'

function typeOf(n: Note): string {
  const t = (n.title || '').toLowerCase()
  const c = (n.category || '').toLowerCase()
  if (t.endsWith('.pdf') || c === 'pdf') return 'pdf'
  if (t.endsWith('.ppt') || t.endsWith('.pptx') || c === 'slides') return 'ppt'
  if (t.endsWith('.doc') || t.endsWith('.docx') || c === 'document') return 'doc'
  if (t.endsWith('.xls') || t.endsWith('.xlsx') || t.endsWith('.csv')) return 'xls'
  if (t.endsWith('.mp4') || t.endsWith('.mov') || t.endsWith('.mkv')) return 'vid'
  if (t.endsWith('.mp3') || t.endsWith('.wav') || t.endsWith('.m4a')) return 'aud'
  if (t.endsWith('.jpg') || t.endsWith('.jpeg') || t.endsWith('.png') || t.endsWith('.webp')) return 'img'
  if (t.endsWith('.py') || t.endsWith('.js') || t.endsWith('.dart') || t.endsWith('.html') || t.endsWith('.json')) return 'code'
  if (t.endsWith('.txt') || t.endsWith('.md')) return 'txt'
  return 'other'
}

const TYPE_META: Record<string, { label: string; color: string }> = {
  pdf: { label: 'PDF', color: '#EF5350' },
  doc: { label: 'DOC', color: '#42A5F5' },
  ppt: { label: 'PPT', color: '#FFA726' },
  xls: { label: 'XLS', color: '#66BB6A' },
  vid: { label: 'VID', color: '#5C6BC0' },
  aud: { label: 'AUD', color: '#EC407A' },
  img: { label: 'IMG', color: '#AB47BC' },
  code: { label: 'CODE', color: '#78909C' },
  txt: { label: 'TXT', color: '#26A69A' },
  other: { label: 'FILE', color: '#90A4AE' },
}

export default function Home() {
  const [notes, setNotes] = useState<Note[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [year, setYear] = useState<number | null>(null)
  const [semester, setSemester] = useState<number | null>(null)
  const [typeFilter, setTypeFilter] = useState<string | null>(null)
  const [years, setYears] = useState<number[]>([])
  const [installEvt, setInstallEvt] = useState<Event | null>(null)
  const [showChat, setShowChat] = useState(false)
  const [chatMsgs, setChatMsgs] = useState<ChatMsg[]>([])
  const [chatInput, setChatInput] = useState('')
  const [chatLoading, setChatLoading] = useState(false)
  const chatRef = useRef<HTMLDivElement>(null)

  // ── Load notes (guests can read all) ──
  useEffect(() => {
    let q = supabase.from('notes').select('*').order('created_at', { ascending: false }).limit(200)
    if (year !== null) q = q.eq('target_year', year)
    if (semester !== null) q = q.eq('semester', semester)
    q.then(({ data, error }) => {
      if (error) console.error('notes fetch', error)
      const rows = (data as Note[]) || []
      setNotes(rows)
      setYears(Array.from(new Set(rows.map((n) => n.target_year).filter((y): y is number => !!y))).sort())
      setLoading(false)
    })
  }, [year, semester])

  // ── Search (debounced client-side on loaded set — 200 notes max) ──
  const filtered = useMemo(() => {
    let list = notes
    if (search.trim()) {
      const s = search.toLowerCase()
      list = list.filter((n) => (n.title || '').toLowerCase().includes(s))
    }
    if (typeFilter) list = list.filter((n) => typeOf(n) === typeFilter)
    return list
  }, [notes, search, typeFilter])

  // ── PWA install prompt (Chrome/Edge) ──
  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault()
      setInstallEvt(e)
    }
    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  // ── Notesy guest history (localStorage) ──
  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey)
      if (raw) setChatMsgs(JSON.parse(raw))
    } catch { /* ignore */ }
  }, [])

  useEffect(() => {
    if (chatRef.current) chatRef.current.scrollTop = chatRef.current.scrollHeight
  }, [chatMsgs, chatLoading])

  const usedCount = chatMsgs.filter((m) => m.role === 'user').length
  const limitReached = usedCount >= GUEST_LIMIT

  async function sendChat() {
    const text = chatInput.trim()
    if (!text || chatLoading || limitReached) return
    const next = [...chatMsgs, { role: 'user' as const, content: text }]
    setChatMsgs(next)
    setChatInput('')
    setChatLoading(true)
    try {
      const res = await fetch(NOTESY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, history: chatMsgs.slice(-5) }),
      })
      const data = await res.json()
      const reply = data?.content || 'Sorry, Notesy hit a snag. Try again?'
      const final = [...next, { role: 'assistant' as const, content: reply }]
      setChatMsgs(final)
      try { localStorage.setItem(storageKey, JSON.stringify(final)) } catch { /* ignore */ }
    } catch (e) {
      setChatMsgs([...next, { role: 'assistant', content: 'Could not reach Notesy. Check your connection.' }])
      console.error(e)
    } finally {
      setChatLoading(false)
    }
  }

  function viewUrl(n: Note): string {
    const url = n.gdrive_id || ''
    let ext = ''
    const m = (n.title || '').match(/\.(pdf|docx|doc|pptx|ppt|txt|md|csv|xlsx|xls|jpg|jpeg|png|mp4|mp3|m4a|mov|mkv|webm)$/i)
    if (m) ext = m[1].toLowerCase()
    return `/view?url=${encodeURIComponent(url)}&ext=${encodeURIComponent(ext)}`
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* ── Top bar (app-like) ── */}
      <header className="bg-white border-b sticky top-0 z-20">
        <div className="max-w-6xl mx-auto px-4 py-3 flex items-center justify-between">
          <a href="/" className="font-bold text-indigo-600 text-lg">NotesCache</a>
          <div className="flex items-center gap-2">
            <a href="/downloads" className="px-3 py-2 text-sm text-gray-600 hover:text-indigo-600 transition">Download App</a>
            {installEvt && (
              <button
                onClick={() => {
                  const evt = installEvt as unknown as { prompt: () => Promise<void> }
                  evt.prompt()
                  setInstallEvt(null)
                }}
                className="px-4 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700 transition"
              >
                Install App
              </button>
            )}
          </div>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 py-6">
        {/* ── Mobile-ish note toolbar ── */}
        <div className="flex flex-wrap items-center gap-2 mb-5">
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search notes…"
            className="flex-1 min-w-[180px] px-4 py-2 rounded-full border border-gray-300 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
          <select
            value={year ?? ''}
            onChange={(e) => setYear(e.target.value ? Number(e.target.value) : null)}
            className="px-3 py-2 rounded-full border border-gray-300 bg-white text-sm"
          >
            <option value="">All years</option>
            {years.map((y) => <option key={y} value={y}>Year {y}</option>)}
          </select>
          <select
            value={semester ?? ''}
            onChange={(e) => setSemester(e.target.value ? Number(e.target.value) : null)}
            className="px-3 py-2 rounded-full border border-gray-300 bg-white text-sm"
          >
            <option value="">All semesters</option>
            <option value={1}>Semester 1</option>
            <option value={2}>Semester 2</option>
          </select>
        </div>

        {/* ── Type filter chips ── */}
        <div className="flex flex-wrap gap-1.5 mb-5">
          <button
            onClick={() => setTypeFilter(null)}
            className={`px-3 py-1 rounded-full text-xs font-medium border transition ${typeFilter === null ? 'bg-indigo-600 text-white border-indigo-600' : 'bg-white text-gray-600 border-gray-300 hover:border-indigo-400'}`}
          >
            All files
          </button>
          {Object.entries(TYPE_META).map(([key, meta]) => (
            <button
              key={key}
              onClick={() => setTypeFilter(typeFilter === key ? null : key)}
              className={`px-3 py-1 rounded-full text-xs font-medium border transition ${typeFilter === key ? 'text-white border-transparent' : 'bg-white text-gray-600 border-gray-300 hover:border-indigo-400'}`}
              style={typeFilter === key ? { backgroundColor: meta.color } : undefined}
            >
              {meta.label}
            </button>
          ))}
        </div>

        {/* ── Notes grid ── */}
        {loading ? (
          <div className="text-center py-20 text-gray-500">Loading notes…</div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20">
            <div className="text-5xl mb-4">📭</div>
            <p className="text-gray-600 font-medium">No notes found</p>
            <p className="text-sm text-gray-500 mt-1">Try a different year, semester, or search term.</p>
          </div>
        ) : (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {filtered.map((n) => {
              const t = typeOf(n)
              const meta = TYPE_META[t]
              const view = viewUrl(n)
              return (
                <a
                  key={n.id}
                  href={view}
                  className="bg-white rounded-2xl border border-gray-200 p-4 hover:shadow-md hover:border-indigo-300 transition flex flex-col gap-2"
                >
                  <div className="flex items-center gap-2">
                    <span
                      className="px-2 py-0.5 rounded-md text-[10px] font-bold text-white"
                      style={{ backgroundColor: meta.color }}
                    >
                      {meta.label}
                    </span>
                    {n.semester ? (
                      <span className="text-[11px] text-gray-500">Sem {n.semester}</span>
                    ) : null}
                  </div>
                  <div className="font-semibold text-gray-900 text-sm leading-snug line-clamp-2">{n.title}</div>
                  <div className="text-xs text-gray-500">
                    {n.lecturer_name ? `By ${n.lecturer_name}` : `Year ${n.target_year ?? '—'}`}
                  </div>
                </a>
              )
            })}
          </div>
        )}

        {/* ── Notesy chat (floating) ── */}
        {showChat && (
          <div className="fixed bottom-4 right-4 w-[92vw] max-w-sm h-[520px] bg-white rounded-2xl shadow-2xl border border-gray-200 flex flex-col z-30 overflow-hidden">
            <div className="px-4 py-3 bg-indigo-600 text-white flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-lg">🤖</span>
                <div>
                  <div className="font-semibold text-sm">Notesy</div>
                  <div className="text-[10px] text-indigo-200">Beta — answers can be imperfect</div>
                </div>
              </div>
              <button onClick={() => setShowChat(false)} className="text-white/80 hover:text-white">✕</button>
            </div>
            <div ref={chatRef} className="flex-1 overflow-y-auto p-3 space-y-2 bg-gray-50">
              {chatMsgs.length === 0 && (
                <div className="text-center text-gray-400 text-xs py-8">
                  Ask about your notes, homework, or any study topic.
                </div>
              )}
              {chatMsgs.map((m, i) => (
                <div key={i} className={`max-w-[85%] px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap ${m.role === 'user' ? 'ml-auto bg-indigo-600 text-white rounded-br-sm' : 'bg-white border border-gray-200 rounded-bl-sm'}`}>
                  {m.content}
                </div>
              ))}
              {chatLoading && <div className="text-xs text-gray-400 px-1">Notesy is thinking…</div>}
            </div>
            <div className="p-3 border-t bg-white">
              {limitReached ? (
                <div className="text-center text-xs text-gray-500 py-2">
                  Demo limit reached. <a href="/downloads" className="text-indigo-600 font-medium">Get the app</a> for the full experience.
                </div>
              ) : (
                <div className="flex gap-2">
                  <input
                    value={chatInput}
                    onChange={(e) => setChatInput(e.target.value)}
                    onKeyDown={(e) => { if (e.key === 'Enter') sendChat() }}
                    placeholder="Ask Notesy…"
                    className="flex-1 px-3 py-2 rounded-full border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
                  />
                  <button
                    onClick={sendChat}
                    disabled={chatLoading}
                    className="px-4 py-2 bg-indigo-600 text-white rounded-full text-sm font-medium hover:bg-indigo-700 disabled:opacity-50 transition"
                  >
                    Send
                  </button>
                </div>
              )}
            </div>
          </div>
        )}
      </main>

      {/* ── Floating Notesy button ── */}
      <button
        onClick={() => setShowChat(!showChat)}
        className="fixed bottom-4 right-4 w-14 h-14 rounded-full bg-indigo-600 text-white text-2xl shadow-lg hover:bg-indigo-700 transition z-30 flex items-center justify-center"
        aria-label="Ask Notesy"
      >
        🤖
      </button>

      {/* iOS hint — Add to Home Screen */}
      {!installEvt && (
        <div className="fixed bottom-20 right-4 z-30 hidden sm:block">
          <a
            href="/downloads"
            className="bg-white border border-gray-200 rounded-xl px-4 py-2 text-xs text-gray-600 shadow-md hover:shadow-lg transition inline-block"
          >
            iPhone? Add this site to your Home Screen to use it like an app ↗
          </a>
        </div>
      )}
    </div>
  )
}
