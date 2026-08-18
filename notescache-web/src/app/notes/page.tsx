'use client'

import { useEffect, useMemo, useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
)

type Note = {
  id: string
  title: string
  lecturer_name?: string
  target_year?: number
  semester?: number
  gdrive_id?: string
  category?: string
  created_at?: string
}

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

export default function NotesPage() {
  const [notes, setNotes] = useState<Note[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [year, setYear] = useState<number | null>(null)
  const [semester, setSemester] = useState<number | null>(null)
  const [typeFilter, setTypeFilter] = useState<string | null>(null)
  const [years, setYears] = useState<number[]>([])

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

  const filtered = useMemo(() => {
    let list = notes
    if (search.trim()) {
      const s = search.toLowerCase()
      list = list.filter((n) => (n.title || '').toLowerCase().includes(s))
    }
    if (typeFilter) list = list.filter((n) => typeOf(n) === typeFilter)
    return list
  }, [notes, search, typeFilter])

  function viewUrl(n: Note): string {
    const url = n.gdrive_id || ''
    let ext = ''
    const m = (n.title || '').match(/\.(pdf|docx|doc|pptx|ppt|txt|md|csv|xlsx|xls|jpg|jpeg|png|mp4|mp3|m4a|mov|mkv|webm)$/i)
    if (m) ext = m[1].toLowerCase()
    return `/view?url=${encodeURIComponent(url)}&ext=${encodeURIComponent(ext)}`
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b sticky top-0 z-20">
        <div className="max-w-5xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Academic Notes</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 py-6">
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
              return (
                <a
                  key={n.id}
                  href={viewUrl(n)}
                  className="bg-white rounded-2xl border border-gray-200 p-4 hover:shadow-md hover:border-indigo-300 transition flex flex-col gap-2"
                >
                  <div className="flex items-center gap-2">
                    <span className="px-2 py-0.5 rounded-md text-[10px] font-bold text-white" style={{ backgroundColor: meta.color }}>
                      {meta.label}
                    </span>
                    {n.semester ? <span className="text-[11px] text-gray-500">Sem {n.semester}</span> : null}
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
      </main>
    </div>
  )
}
