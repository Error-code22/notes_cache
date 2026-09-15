'use client'

import { Suspense, useEffect, useMemo, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { useAuth, supabase } from '../../lib/auth'
import { hasStaffVisibility, noteType, TYPE_META } from '../../lib/utils'
import AppShell from '../../components/AppShell'
import { SearchIcon } from '../../components/icons'

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

function NotesPageInner() {
  const { user, profile, loading: authLoading } = useAuth()
  const searchParams = useSearchParams()
  const [notes, setNotes] = useState<Note[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [semester, setSemester] = useState<number | null>(null)
  const [typeFilter, setTypeFilter] = useState<string | null>(null)
  const [scope, setScope] = useState<'all' | 'mine'>(
    searchParams.get('mine') === '1' ? 'mine' : 'all',
  )
  const [err, setErr] = useState('')

  const isGuest = !user
  const staff = hasStaffVisibility(profile?.role)
  const yearLevel = profile?.year_level

  useEffect(() => {
    const t = setTimeout(() => setDebounced(search), 350)
    return () => clearTimeout(t)
  }, [search])

  useEffect(() => {
    if (authLoading) return
    ;(async () => {
      setLoading(true)
      setErr('')
      try {
        let q = supabase.from('notes').select('*').order('created_at', { ascending: false }).limit(300)
        if (semester !== null) q = q.eq('semester', semester)
        if (debounced.trim()) q = q.ilike('title', `%${debounced.trim()}%`)

        if (scope === 'mine' && user) {
          // Always show the signed-in user's uploads
          q = q.eq('user_id', user.id)
        } else if (!staff && user && yearLevel != null) {
          // Year isolation, but keep own uploads visible (matches the app)
          q = q.or(`user_id.eq.${user.id},target_year.eq.${yearLevel}`)
        } else if (!staff && !user) {
          // Guests browse whatever public RLS allows (no year profile)
        }

        const { data, error: qErr } = await q
        if (qErr) throw qErr
        setNotes((data as Note[]) || [])
      } catch (e) {
        console.error('notes fetch', e)
        setNotes([])
        setErr(e instanceof Error ? e.message : 'Failed to load notes')
      }
      setLoading(false)
    })()
  }, [authLoading, semester, scope, debounced, staff, yearLevel, user])

  const filtered = useMemo(() => {
    if (!typeFilter) return notes
    return notes.filter((n) => noteType(n.title, n.category) === typeFilter)
  }, [notes, typeFilter])

  return (
    <AppShell title="Academic Notes" wide
      action={staff || user ? (
        <a href="/donate" className="text-xs font-bold px-3 py-1.5 rounded-full bg-indigo-600 text-white hover:bg-indigo-700 transition shrink-0">
          UPLOAD
        </a>
      ) : undefined}
    >
      {!isGuest && !staff && yearLevel != null && scope === 'all' && (
        <div className="mb-4 text-[12px] text-gray-500 dark:text-gray-400">
          Showing Year {yearLevel} materials + your uploads
        </div>
      )}
      {err && <p className="mb-4 text-sm text-red-600">{err}</p>}

      <div className="flex flex-wrap items-center gap-2 mb-4">
        <div className="flex-1 min-w-[180px] relative">
          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400"><SearchIcon size={18} /></span>
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search notes…"
            className="w-full pl-9 pr-4 py-2 rounded-full border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <select value={semester ?? ''} onChange={(e) => setSemester(e.target.value ? Number(e.target.value) : null)} className="px-3 py-2 rounded-full border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white">
          <option value="">All semesters</option>
          <option value={1}>Semester 1</option>
          <option value={2}>Semester 2</option>
        </select>
      </div>

      <div className="flex flex-wrap gap-1.5 mb-3">
        <Chip active={scope === 'all'} onClick={() => setScope('all')}>All Notes</Chip>
        {!isGuest && <Chip active={scope === 'mine'} onClick={() => setScope('mine')}>My Notes</Chip>}
      </div>

      <div className="flex flex-wrap gap-1.5 mb-5">
        <Chip active={typeFilter === null} onClick={() => setTypeFilter(null)}>All files</Chip>
        {Object.entries(TYPE_META).map(([key, meta]) => (
          <Chip key={key} active={typeFilter === key} onClick={() => setTypeFilter(typeFilter === key ? null : key)} color={meta.color}>
            {meta.label}
          </Chip>
        ))}
      </div>

      {loading ? (
        <div className="text-center py-16 text-gray-400">Loading…</div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-16">
          <div className="flex justify-center text-gray-300 mb-4"><SearchIcon size={48} /></div>
          <p className="text-gray-600 dark:text-gray-300 font-medium">No notes found</p>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">Try a different semester or search term.</p>
        </div>
      ) : (
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((n) => {
            const t = noteType(n.title, n.category)
            const meta = TYPE_META[t]
            return (
              <a key={n.id} href={`/note?id=${n.id}`} className="bg-white dark:bg-[#1C1C1E] rounded-2xl border border-gray-200 dark:border-white/10 p-4 hover:shadow-md hover:border-indigo-300 transition flex flex-col gap-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="px-2 py-0.5 rounded-md text-[10px] font-bold text-white" style={{ backgroundColor: meta.color }}>{meta.label}</span>
                  <span className="text-[11px] text-gray-500 dark:text-gray-400">Year {n.target_year ?? '—'}</span>
                  {n.semester ? <span className="text-[11px] text-gray-500 dark:text-gray-400">Sem {n.semester}</span> : null}
                  {n.summary ? <span className="text-[10px] px-1.5 py-0.5 rounded bg-violet-500/10 text-violet-600">AI</span> : null}
                </div>
                <div className="font-semibold text-gray-900 dark:text-white text-sm leading-snug line-clamp-2">{n.title}</div>
                <div className="text-xs text-gray-500 dark:text-gray-400">{n.lecturer_name || '—'}</div>
              </a>
            )
          })}
        </div>
      )}
    </AppShell>
  )
}

function Chip({ active, onClick, children, color }: { active: boolean; onClick: () => void; children: React.ReactNode; color?: string }) {
  return (
    <button
      onClick={onClick}
      className={`px-3 py-1 rounded-full text-xs font-medium border transition ${active ? 'text-white border-transparent' : 'bg-white dark:bg-[#1C1C1E] text-gray-600 dark:text-gray-300 border-gray-300 dark:border-white/15 hover:border-indigo-400'}`}
      style={active ? { backgroundColor: color || '#4F46E5' } : undefined}
    >
      {children}
    </button>
  )
}

export default function NotesPage() {
  return (
    <Suspense fallback={<div className="min-h-screen flex items-center justify-center text-gray-400">Loading…</div>}>
      <NotesPageInner />
    </Suspense>
  )
}
