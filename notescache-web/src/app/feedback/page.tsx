'use client'

import { useState } from 'react'
import { useAuth, supabase } from '../../lib/auth'
import AppShell from '../../components/AppShell'
import { BugIcon, MegaphoneIcon } from '../../components/icons'

export default function FeedbackPage() {
  const { user } = useAuth()
  const [type, setType] = useState<'bug' | 'feature'>('bug')
  const [content, setContent] = useState('')
  const [busy, setBusy] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState('')

  async function submit() {
    if (!content.trim()) return
    setBusy(true)
    setError('')
    const row: Record<string, unknown> = { type, content: content.trim(), created_at: new Date().toISOString() }
    if (user) row.user_id = user.id
    const { error: err } = await supabase.from('app_feedback').insert(row)
    setBusy(false)
    if (err) { setError(err.message); return }
    setDone(true)
    setContent('')
  }

  return (
    <AppShell title="Bug Report & Feedback">
      {done ? (
        <div className="text-center py-16">
          <div className="text-4xl mb-3">✓</div>
          <h2 className="font-bold text-gray-900 dark:text-white mb-1">Feedback sent!</h2>
          <p className="text-sm text-gray-500 mb-4">Thank you.</p>
          <button onClick={() => setDone(false)} className="text-sm text-indigo-600 font-medium">Send another</button>
        </div>
      ) : (
        <>
          <h2 className="text-lg font-bold text-gray-900 dark:text-white mb-4">What would you like to report?</h2>
          <div className="flex gap-3 mb-6">
            <TypeCard active={type === 'bug'} onClick={() => setType('bug')} color="#EF5350" icon={<BugIcon size={22} />} label="Bug Report" />
            <TypeCard active={type === 'feature'} onClick={() => setType('feature')} color="#42A5F5" icon={<MegaphoneIcon size={22} />} label="New Feature" />
          </div>
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            rows={8}
            placeholder="Describe the bug or your feature idea…"
            className="w-full px-4 py-3 rounded-2xl border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white mb-4"
          />
          {error && <p className="text-sm text-red-600 mb-3">{error}</p>}
          <button onClick={submit} disabled={busy || !content.trim()} className="w-full py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold disabled:opacity-50">
            {busy ? 'Sending…' : 'SUBMIT FEEDBACK'}
          </button>
        </>
      )}
    </AppShell>
  )
}

function TypeCard({ active, onClick, color, icon, label }: { active: boolean; onClick: () => void; color: string; icon: React.ReactNode; label: string }) {
  return (
    <button
      onClick={onClick}
      className="flex-1 py-4 rounded-2xl border text-center transition"
      style={{
        backgroundColor: active ? color : `${color}1A`,
        borderColor: `${color}80`,
        color: active ? '#fff' : color,
      }}
    >
      <div className="flex justify-center mb-1">{icon}</div>
      <div className="text-xs font-bold">{label}</div>
    </button>
  )
}
