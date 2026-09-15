'use client'

import { useEffect, useState } from 'react'
import { useAuth, supabase } from '../../lib/auth'
import AppShell from '../../components/AppShell'
import {
  DashboardIcon, GroupIcon, ForumIcon, BookIcon, BrainIcon, CloudIcon,
  MonitorIcon, HeadsetIcon, MegaphoneIcon, CardIcon, ConstructionIcon, DocIcon,
} from '../../components/icons'

type ProfileRow = { id: string; full_name?: string; role?: string }

export default function AdminDashboardPage() {
  const { user, profile, loading } = useAuth()
  const isAdmin = String(profile?.role || '').toLowerCase().includes('admin')
  const [section, setSection] = useState<string | null>(null)
  const [stats, setStats] = useState({ users: 0, notes: 0 })
  const [feedback, setFeedback] = useState<{ id: string; type?: string; content?: string; created_at?: string; full_name?: string }[]>([])
  const [users, setUsers] = useState<ProfileRow[]>([])
  const [updates, setUpdates] = useState<{ id: string; title?: string; content?: string; created_at?: string }[]>([])
  const [roadmap, setRoadmap] = useState<{ id: string; title?: string; description?: string }[]>([])
  const [plans, setPlans] = useState<{ id: string; name?: string; price?: string }[]>([])
  const [cfg, setCfg] = useState<Record<string, string>>({})
  const [msg, setMsg] = useState('')
  const [testOut, setTestOut] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!isAdmin) return
    ;(async () => {
      const [{ count: uc }, { count: nc }, { data: config }] = await Promise.all([
        supabase.from('profiles').select('*', { count: 'exact', head: true }),
        supabase.from('notes').select('*', { count: 'exact', head: true }),
        supabase.from('app_config').select('key, value'),
      ])
      setStats({ users: uc || 0, notes: nc || 0 })
      const map: Record<string, string> = {}
      ;((config as { key: string; value: string }[]) || []).forEach((r) => { map[r.key] = r.value })
      setCfg(map)
    })()
  }, [isAdmin])

  useEffect(() => {
    if (!isAdmin || !section) return
    ;(async () => {
      if (section === 'feedback') {
        try {
          const { data } = await supabase.rpc('list_feedback')
          setFeedback((data as typeof feedback) || [])
        } catch {
          const { data } = await supabase.from('app_feedback').select('*').order('created_at', { ascending: false }).limit(100)
          setFeedback((data as typeof feedback) || [])
        }
      }
      if (section === 'users') {
        const { data } = await supabase.from('profiles').select('id, full_name, role').limit(200)
        setUsers((data as ProfileRow[]) || [])
      }
      if (section === 'updates') {
        const { data } = await supabase.from('app_updates').select('*').order('created_at', { ascending: false }).limit(50)
        setUpdates((data as typeof updates) || [])
      }
      if (section === 'roadmap') {
        const { data } = await supabase.from('roadmap_items').select('*').order('sort_order')
        setRoadmap((data as typeof roadmap) || [])
      }
      if (section === 'plans') {
        const { data } = await supabase.from('pricing_plans').select('*').order('sort_order')
        setPlans((data as typeof plans) || [])
      }
    })()
  }, [section, isAdmin])

  async function setConfig(key: string, value: string) {
    setCfg((c) => ({ ...c, [key]: value }))
    const { error } = await supabase.from('app_config').upsert({ key, value }, { onConflict: 'key' })
    setMsg(error ? error.message : `Saved ${key}`)
  }

  async function setUserRole(id: string, role: string) {
    const { error } = await supabase.from('profiles').update({ role }).eq('id', id)
    if (!error) setUsers((us) => us.map((u) => (u.id === id ? { ...u, role } : u)))
    setMsg(error ? error.message : 'Role updated')
  }

  async function testModel() {
    setBusy(true); setTestOut('')
    try {
      const session = await supabase.auth.getSession()
      const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.data.session?.access_token}`,
        },
        body: JSON.stringify({
          action: 'test_model',
          provider: cfg.ai_text_provider || 'groq',
          model: cfg.ai_model || 'openai/gpt-oss-120b',
          message: 'Reply with a short greeting.',
        }),
      })
      const data = await res.json()
      setTestOut(data?.content || data?.error || JSON.stringify(data))
    } catch (e) {
      setTestOut(e instanceof Error ? e.message : 'Failed')
    } finally { setBusy(false) }
  }

  async function cleanupSummaries() {
    setBusy(true)
    try {
      const session = await supabase.auth.getSession()
      const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.data.session?.access_token}`,
        },
        body: JSON.stringify({ action: 'cleanup_summaries' }),
      })
      const data = await res.json()
      setMsg(`Cleaned ${data.cleaned ?? 0}, cleared ${data.cleared ?? 0}`)
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Failed')
    } finally { setBusy(false) }
  }

  async function batchConvertPdf() {
    setBusy(true)
    setMsg('Converting slides to PDF… this can take a while.')
    try {
      const session = await supabase.auth.getSession()
      const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${session.data.session?.access_token}`,
        },
        body: JSON.stringify({ action: 'batch_convert_to_pdf' }),
      })
      const data = await res.json()
      if (data?.error) setMsg(String(data.error))
      else setMsg(`Converted ${data.converted ?? 0}/${data.total ?? 0}, failed ${data.failed ?? 0}${data.errors?.length ? ` — ${data.errors.slice(0, 3).join('; ')}` : ''}`)
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Failed')
    } finally { setBusy(false) }
  }

  async function addUpdate() {
    const title = window.prompt('Announcement title')
    if (!title) return
    const content = window.prompt('Content') || ''
    const { error } = await supabase.from('app_updates').insert({ title, content, created_at: new Date().toISOString() })
    if (!error) {
      const { data } = await supabase.from('app_updates').select('*').order('created_at', { ascending: false }).limit(50)
      setUpdates((data as typeof updates) || [])
    }
    setMsg(error ? error.message : 'Posted')
  }

  if (loading) return <AppShell title="Admin"><div className="text-center py-16 text-gray-400">Loading…</div></AppShell>
  if (!user || !isAdmin) {
    return (
      <AppShell title="Admin">
        <div className="text-center py-20 text-gray-500">
          <p className="font-bold mb-2">Admins only</p>
          <a href="/login" className="text-indigo-600 text-sm font-medium">Sign in as admin</a>
        </div>
      </AppShell>
    )
  }

  if (section) {
    return (
      <AppShell title={SECTION_TITLES[section] || 'Admin'} wide action={
        <button onClick={() => setSection(null)} className="text-xs font-bold text-indigo-600 shrink-0">GRID</button>
      }>
        {msg && <div className="mb-4 text-sm text-indigo-700 bg-indigo-50 dark:bg-indigo-500/10 rounded-xl px-3 py-2">{msg}</div>}
        {renderSection(section, { cfg, setConfig, feedback, users, setUserRole, updates, addUpdate, roadmap, plans, testModel, cleanupSummaries, batchConvertPdf, testOut, busy, stats })}
      </AppShell>
    )
  }

  const cards = [
    { id: 'command', name: 'Command Center', desc: 'KPIs, usage & health', color: '#5C6BC0', icon: DashboardIcon },
    { id: 'users', name: 'User Hub', desc: 'Roles & verification', color: '#26A69A', icon: GroupIcon },
    { id: 'feedback', name: 'Feedback Central', desc: 'Bug reports & ideas', color: '#42A5F5', icon: ForumIcon },
    { id: 'vault', name: 'Content Vault', desc: 'Notes & backups', color: '#66BB6A', icon: BookIcon },
    { id: 'ai', name: 'AI Control Room', desc: 'Model & limits', color: '#AB47BC', icon: BrainIcon },
    { id: 'cloud', name: 'Cloud Status', desc: 'Storage & bandwidth', color: '#EF5350', icon: CloudIcon },
    { id: 'health', name: 'System Health', desc: 'Feature toggles', color: '#EC407A', icon: MonitorIcon },
    { id: 'help', name: 'Help & Support', desc: 'Contact channels', color: '#FFA726', icon: HeadsetIcon },
    { id: 'updates', name: 'App Updates', desc: 'Announcements', color: '#7E57C2', icon: MegaphoneIcon },
    { id: 'plans', name: 'Plans', desc: 'Pricing tiers', color: '#26C6DA', icon: CardIcon },
    { id: 'roadmap', name: 'Roadmap', desc: 'Feature plans', color: '#26A69A', icon: ConstructionIcon },
    { id: 'docs', name: 'Docs & Legal', desc: 'About, terms & privacy', color: '#8D6E63', icon: DocIcon },
  ]

  return (
    <AppShell title="Admin Command Center" wide>
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-3">
        {cards.map((c) => (
          <button key={c.id} onClick={() => setSection(c.id)} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 text-left hover:shadow-md transition">
            <div className="w-10 h-10 rounded-xl flex items-center justify-center mb-3" style={{ backgroundColor: `${c.color}1A`, color: c.color }}>
              <c.icon size={22} />
            </div>
            <div className="font-bold text-sm text-gray-900 dark:text-white">{c.name}</div>
            <div className="text-[11px] text-gray-500 mt-0.5">{c.desc}</div>
          </button>
        ))}
      </div>
    </AppShell>
  )
}

const SECTION_TITLES: Record<string, string> = {
  command: 'Command Center',
  users: 'User Hub',
  feedback: 'Feedback Central',
  vault: 'Content Vault',
  ai: 'AI Control Room',
  cloud: 'Cloud Status',
  health: 'System Health',
  help: 'Help & Support',
  updates: 'App Updates',
  plans: 'Plans',
  roadmap: 'Roadmap',
  docs: 'Docs & Legal',
}

type SecProps = {
  cfg: Record<string, string>
  setConfig: (k: string, v: string) => Promise<void>
  feedback: { id: string; type?: string; content?: string; created_at?: string; full_name?: string }[]
  users: ProfileRow[]
  setUserRole: (id: string, role: string) => Promise<void>
  updates: { id: string; title?: string; content?: string; created_at?: string }[]
  addUpdate: () => Promise<void>
  roadmap: { id: string; title?: string; description?: string }[]
  plans: { id: string; name?: string; price?: string }[]
  testModel: () => Promise<void>
  cleanupSummaries: () => Promise<void>
  batchConvertPdf: () => Promise<void>
  testOut: string
  busy: boolean
  stats: { users: number; notes: number }
}

function renderSection(section: string, p: SecProps) {
  if (section === 'command') {
    return (
      <div className="grid grid-cols-2 gap-4">
        <Kpi label="Users" value={p.stats.users} />
        <Kpi label="Notes" value={p.stats.notes} />
      </div>
    )
  }
  if (section === 'users') {
    return (
      <div className="space-y-2">
        {p.users.map((u) => (
          <div key={u.id} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4">
            <div className="font-semibold text-sm text-gray-900 dark:text-white">{u.full_name || u.id.slice(0, 8)}</div>
            <div className="text-[11px] text-gray-400 mb-2">{u.id.slice(0, 12)}… · {u.role || 'student'}</div>
            <div className="flex flex-wrap gap-1">
              {['student', 'lecturer', 'moderator', 'admin'].map((r) => (
                <button key={r} onClick={() => {
                  const roles = String(u.role || 'student').split(',').map((x) => x.trim().toLowerCase()).filter(Boolean)
                  const next = roles.includes(r) ? roles.filter((x) => x !== r) : [...roles, r]
                  p.setUserRole(u.id, next.length ? next.join(', ') : 'student')
                }} className={`px-2 py-1 rounded-lg text-[10px] font-bold ${String(u.role || '').toLowerCase().includes(r) ? 'bg-indigo-600 text-white' : 'bg-gray-100 dark:bg-white/10 text-gray-500'}`}>
                  {r}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
    )
  }
  if (section === 'feedback') {
    return (
      <div className="space-y-2">
        {p.feedback.map((f) => (
          <div key={f.id} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4">
            <div className="text-[11px] font-bold text-indigo-600 mb-1">{f.type || 'bug'} · {f.full_name || 'guest'}</div>
            <div className="text-sm text-gray-800 dark:text-gray-200">{f.content}</div>
            {f.created_at && <div className="text-[10px] text-gray-400 mt-1">{new Date(f.created_at).toLocaleString()}</div>}
          </div>
        ))}
        {!p.feedback.length && <div className="text-gray-400 text-sm py-8 text-center">No feedback yet.</div>}
      </div>
    )
  }
  if (section === 'ai') {
    return (
      <div className="space-y-4">
        <Field label="Text provider" value={p.cfg.ai_text_provider || 'groq'} onSave={(v) => p.setConfig('ai_text_provider', v)} />
        <Field label="Text model" value={p.cfg.ai_model || 'openai/gpt-oss-120b'} onSave={(v) => p.setConfig('ai_model', v)} />
        <Field label="Fallback provider" value={p.cfg.ai_text_fallback_provider || ''} onSave={(v) => p.setConfig('ai_text_fallback_provider', v)} />
        <Field label="Fallback model" value={p.cfg.ai_text_fallback_model || ''} onSave={(v) => p.setConfig('ai_text_fallback_model', v)} />
        <Field label="Vision model" value={p.cfg.ai_vision_model || 'qwen/qwen3.6-27b'} onSave={(v) => p.setConfig('ai_vision_model', v)} />
        <Field label="Daily text limit" value={p.cfg.ai_daily_text_limit || '50'} onSave={(v) => p.setConfig('ai_daily_text_limit', v)} />
        <Field label="Daily image limit" value={p.cfg.ai_daily_image_limit || '10'} onSave={(v) => p.setConfig('ai_daily_image_limit', v)} />
        <div className="flex gap-2">
          <button onClick={p.testModel} disabled={p.busy} className="flex-1 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold disabled:opacity-50">Test Model</button>
          <button onClick={p.cleanupSummaries} disabled={p.busy} className="flex-1 py-3 border border-violet-500 text-violet-600 rounded-xl text-sm font-bold disabled:opacity-50">Cleanup Summaries</button>
        </div>
        {p.testOut && <pre className="text-xs bg-black/5 dark:bg-white/5 rounded-xl p-3 whitespace-pre-wrap">{p.testOut}</pre>}
      </div>
    )
  }
  if (section === 'health') {
    return (
      <div className="space-y-4">
        <ToggleRow label="Show Communication button" value={p.cfg.show_comms_button !== 'false'} onChange={(v) => p.setConfig('show_comms_button', v ? 'true' : 'false')} />
        <ToggleRow label="Chat beta locked" value={p.cfg.chat_beta_locked === 'true'} onChange={(v) => p.setConfig('chat_beta_locked', v ? 'true' : 'false')} />
      </div>
    )
  }
  if (section === 'help') {
    return (
      <div className="space-y-4">
        <Field label="Support email" value={p.cfg.support_email || ''} onSave={(v) => p.setConfig('support_email', v)} />
        <Field label="Support phone" value={p.cfg.support_phone || ''} onSave={(v) => p.setConfig('support_phone', v)} />
        <Field label="WhatsApp" value={p.cfg.support_whatsapp || ''} onSave={(v) => p.setConfig('support_whatsapp', v)} />
        <Field label="WhatsApp group" value={p.cfg.whatsapp_group_link || ''} onSave={(v) => p.setConfig('whatsapp_group_link', v)} />
        <Field label="M-Pesa" value={p.cfg.mpesa_no || ''} onSave={(v) => p.setConfig('mpesa_no', v)} />
      </div>
    )
  }
  if (section === 'updates') {
    return (
      <div>
        <button onClick={p.addUpdate} className="mb-4 px-4 py-2 bg-indigo-600 text-white rounded-xl text-sm font-bold">+ New Announcement</button>
        <div className="space-y-2">
          {p.updates.map((u) => (
            <div key={u.id} className="bg-white dark:bg-[#1C1C1E] border rounded-2xl p-4">
              <div className="font-bold text-sm">{u.title}</div>
              <div className="text-sm text-gray-500 mt-1">{u.content}</div>
            </div>
          ))}
        </div>
      </div>
    )
  }
  if (section === 'plans') {
    return (
      <div className="space-y-2">
        {p.plans.map((pl) => (
          <div key={pl.id} className="bg-white dark:bg-[#1C1C1E] border rounded-2xl p-4 flex justify-between">
            <span className="font-semibold text-sm">{pl.name}</span>
            <span className="text-sm text-gray-500">{pl.price}</span>
          </div>
        ))}
        {!p.plans.length && <div className="text-sm text-gray-400 py-6 text-center">No plans in DB (UI uses static pricing page).</div>}
      </div>
    )
  }
  if (section === 'roadmap') {
    return (
      <div className="space-y-2">
        {p.roadmap.map((r) => (
          <div key={r.id} className="bg-white dark:bg-[#1C1C1E] border rounded-2xl p-4">
            <div className="font-semibold text-sm">{r.title}</div>
            <div className="text-xs text-gray-500 mt-1">{r.description}</div>
          </div>
        ))}
      </div>
    )
  }
  if (section === 'vault' || section === 'cloud') {
    return (
      <div className="text-sm text-gray-500 space-y-3">
        <p>Notes in library: {p.stats.notes}</p>
        <p className="text-xs">
          New PPTX uploads convert to PDF in the browser and store both files
          (<code>gdrive_id</code> = original, <code>pdf_url</code> = PDF).
          Web &amp; in-app open the PDF; external readers use the original PPTX.
        </p>
        <a href="/notes" className="inline-block px-4 py-2 bg-indigo-600 text-white rounded-xl text-sm font-bold">Open Notes Library</a>
      </div>
    )
  }
  if (section === 'docs') {
    return (
      <div className="space-y-4">
        <Field label="About text" value={p.cfg.about_text || ''} onSave={(v) => p.setConfig('about_text', v)} textarea />
        <Field label="Terms" value={p.cfg.terms_and_conditions || ''} onSave={(v) => p.setConfig('terms_and_conditions', v)} textarea />
        <Field label="Privacy" value={p.cfg.privacy_policy || ''} onSave={(v) => p.setConfig('privacy_policy', v)} textarea />
      </div>
    )
  }
  return <div className="text-sm text-gray-400">Coming soon on web.</div>
}

function Kpi({ label, value }: { label: string; value: number }) {
  return (
    <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-5">
      <div className="text-2xl font-black text-gray-900 dark:text-white">{value}</div>
      <div className="text-xs text-gray-500 mt-1">{label}</div>
    </div>
  )
}

function Field({ label, value, onSave, textarea }: { label: string; value: string; onSave: (v: string) => Promise<void>; textarea?: boolean }) {
  const [v, setV] = useState(value)
  useEffect(() => setV(value), [value])
  return (
    <div>
      <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">{label}</label>
      {textarea ? (
        <textarea value={v} onChange={(e) => setV(e.target.value)} rows={4} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
      ) : (
        <input value={v} onChange={(e) => setV(e.target.value)} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
      )}
      <button onClick={() => onSave(v)} className="mt-1 text-xs text-indigo-600 font-bold">Save</button>
    </div>
  )
}

function ToggleRow({ label, value, onChange }: { label: string; value: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-center justify-between bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl px-4 py-3">
      <span className="text-sm text-gray-900 dark:text-white">{label}</span>
      <button onClick={() => onChange(!value)} className={`px-3 py-1.5 rounded-xl text-xs font-bold ${value ? 'bg-emerald-600 text-white' : 'bg-gray-200 dark:bg-white/10 text-gray-500'}`}>
        {value ? 'ON' : 'OFF'}
      </button>
    </div>
  )
}
