'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth, signOut, supabase } from '../../lib/auth'
import { useTheme } from '../../lib/theme'
import AppShell from '../../components/AppShell'

export default function SettingsPage() {
  const { user, profile } = useAuth()
  const { mode, toggle } = useTheme()
  const router = useRouter()
  const [profilePublic, setProfilePublic] = useState(true)
  const [msg, setMsg] = useState('')
  const [usage, setUsage] = useState<{ text_count: number; image_count: number } | null>(null)

  useEffect(() => {
    setProfilePublic(profile?.is_profile_public !== false)
  }, [profile])

  useEffect(() => {
    if (!user) return
    supabase.from('user_ai_usage').select('text_count,image_count').eq('user_id', user.id).maybeSingle()
      .then(({ data }) => setUsage(data as { text_count: number; image_count: number } | null))
  }, [user])

  async function togglePublic() {
    if (!user) return
    const next = !profilePublic
    setProfilePublic(next)
    const { error } = await supabase.from('profiles').update({ is_profile_public: next }).eq('id', user.id)
    if (error) setMsg(error.message)
  }

  async function changePassword() {
    if (!user?.email) return
    const pw = window.prompt('New password (min 6 characters)')
    if (!pw || pw.length < 6) return
    const { error } = await supabase.auth.updateUser({ password: pw })
    setMsg(error ? error.message : 'Password updated.')
  }

  async function resetPasswordEmail() {
    if (!user?.email) return
    const { error } = await supabase.auth.resetPasswordForEmail(user.email, {
      redirectTo: `${window.location.origin}/login`,
    })
    setMsg(error ? error.message : 'Reset email sent.')
  }

  return (
    <AppShell title="Settings">
      {msg && <div className="mb-4 text-sm text-indigo-700 dark:text-indigo-300 bg-indigo-50 dark:bg-indigo-500/10 rounded-xl px-3 py-2">{msg}</div>}

      <Section title="Appearance">
        <Row label="Theme" hint={mode === 'dark' ? 'Dark' : 'Light'}>
          <button onClick={toggle} className="px-3 py-1.5 rounded-xl bg-indigo-600 text-white text-xs font-bold">
            {mode === 'dark' ? 'Switch to Light' : 'Switch to Dark'}
          </button>
        </Row>
      </Section>

      <Section title="Account">
        <Row label="Edit Profile" hint={profile?.full_name || 'Student'}>
          <a href="/profile" className="text-sm text-indigo-600 font-medium">Open</a>
        </Row>
        <Row label="Public profile" hint={profilePublic ? 'Visible to others' : 'Private'}>
          <button onClick={togglePublic} className={`px-3 py-1.5 rounded-xl text-xs font-bold ${profilePublic ? 'bg-emerald-600 text-white' : 'bg-gray-200 dark:bg-white/10 text-gray-600 dark:text-gray-300'}`}>
            {profilePublic ? 'ON' : 'OFF'}
          </button>
        </Row>
        <Row label="Change password">
          <button onClick={changePassword} className="text-sm text-indigo-600 font-medium">Set new</button>
        </Row>
        <Row label="Email reset link" hint={user?.email || ''}>
          <button onClick={resetPasswordEmail} className="text-sm text-indigo-600 font-medium">Send</button>
        </Row>
        {user && (
          <Row label="Sign out">
            <button
              onClick={async () => { await signOut(); router.push('/') }}
              className="text-sm text-red-600 font-bold"
            >Sign Out</button>
          </Row>
        )}
      </Section>

      <Section title="AI & Usage">
        <Row label="Text messages today" hint={usage ? String(usage.text_count) : '—'} />
        <Row label="Image messages today" hint={usage ? String(usage.image_count) : '—'} />
        {!user && <p className="text-xs text-gray-500 px-1">Sign in to track usage.</p>}
      </Section>

      <Section title="Support">
        <Row label="Report a bug"><a href="/feedback" className="text-sm text-indigo-600 font-medium">Open</a></Row>
        <Row label="Plans & pricing"><a href="/pricing" className="text-sm text-indigo-600 font-medium">Open</a></Row>
        <Row label="App updates"><a href="/updates" className="text-sm text-indigo-600 font-medium">Open</a></Row>
        <Row label="Download the app"><a href="/downloads" className="text-sm text-indigo-600 font-medium">Open</a></Row>
        <Row label="WhatsApp support">
          <a href="https://wa.me/254703300084" target="_blank" rel="noopener noreferrer" className="text-sm text-indigo-600 font-medium">Chat</a>
        </Row>
      </Section>

      {!user && (
        <a href="/login" className="block text-center mt-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold">Sign in for full settings</a>
      )}
    </AppShell>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6">
      <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wide mb-2 px-1">{title}</div>
      <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl overflow-hidden divide-y divide-black/5 dark:divide-white/5">
        {children}
      </div>
    </div>
  )
}

function Row({ label, hint, children }: { label: string; hint?: string; children?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-3">
      <div className="min-w-0">
        <div className="text-sm font-medium text-gray-900 dark:text-white">{label}</div>
        {hint ? <div className="text-xs text-gray-500 dark:text-gray-400 truncate">{hint}</div> : null}
      </div>
      <div className="shrink-0">{children}</div>
    </div>
  )
}
