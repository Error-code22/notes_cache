'use client'

import { useEffect, useState } from 'react'
import { useAuth, signOut, supabase } from '../../lib/auth'
import { parseRoles } from '../../lib/utils'
import AppShell from '../../components/AppShell'
import { UserIcon } from '../../components/icons'

export default function ProfilePage() {
  const { user, profile, loading } = useAuth()
  const [name, setName] = useState('')
  const [bio, setBio] = useState('')
  const [year, setYear] = useState(1)
  const [friendCode, setFriendCode] = useState('')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')
  const [uploads, setUploads] = useState<{ id: string; title: string; created_at?: string }[]>([])
  const [tab, setTab] = useState<'activity' | 'settings'>('activity')

  useEffect(() => {
    setName(profile?.full_name || '')
    setBio(profile?.bio || '')
    setYear(profile?.year_level || 1)
  }, [profile])

  useEffect(() => {
    if (!user) return
    supabase.from('profiles').select('friend_code').eq('id', user.id).maybeSingle()
      .then(({ data }) => setFriendCode((data as { friend_code?: string })?.friend_code || ''))
    supabase.from('notes').select('id, title, created_at').eq('user_id', user.id).order('created_at', { ascending: false }).limit(30)
      .then(({ data }) => setUploads((data as typeof uploads) || []))
  }, [user])

  async function save() {
    if (!user) return
    setSaving(true)
    setMsg('')
    const { error } = await supabase.from('profiles').update({
      full_name: name.trim() || profile?.full_name,
      bio: bio.trim(),
      year_level: year,
    }).eq('id', user.id)
    setMsg(error ? error.message : 'Profile updated!')
    setSaving(false)
  }

  if (loading) return <AppShell title="Profile"><div className="text-center py-16 text-gray-400">Loading…</div></AppShell>

  if (!user) {
    return (
      <AppShell title="Profile">
        <div className="text-center py-20">
          <div className="flex justify-center mb-4 text-gray-300"><UserIcon size={48} /></div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-white mb-2">Sign in to see your profile</h1>
          <a href="/login" className="inline-block px-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold">Sign In</a>
        </div>
      </AppShell>
    )
  }

  const roles = parseRoles(profile?.role)
  const isAdmin = roles.includes('ADMIN')

  return (
    <AppShell title="My Profile"
      action={isAdmin ? <a href="/admin" className="text-xs font-bold px-3 py-1.5 rounded-full bg-emerald-600 text-white shrink-0">ADMIN</a> : undefined}
    >
      <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-3xl p-6 mb-5">
        <div className="flex items-center gap-4 mb-4">
          {profile?.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={profile.avatar_url} alt="" className="w-16 h-16 rounded-2xl object-cover" />
          ) : (
            <div className="w-16 h-16 rounded-2xl bg-indigo-600/10 flex items-center justify-center text-2xl font-bold text-indigo-600">
              {(profile?.full_name || user.email || 'S')[0].toUpperCase()}
            </div>
          )}
          <div className="min-w-0">
            <div className="font-bold text-lg text-gray-900 dark:text-white truncate">{profile?.full_name || 'Student'}</div>
            <div className="text-xs text-gray-500 truncate">{user.email}</div>
            <div className="flex flex-wrap gap-1 mt-1">
              {roles.map((r) => (
                <span key={r} className="px-1.5 py-0.5 rounded bg-indigo-600/10 text-indigo-600 text-[10px] font-bold">{r}</span>
              ))}
              {!roles.length && <span className="px-1.5 py-0.5 rounded bg-gray-200 dark:bg-white/10 text-[10px] font-bold">STUDENT</span>}
            </div>
          </div>
        </div>
        {friendCode && (
          <button
            onClick={() => navigator.clipboard?.writeText(friendCode)}
            className="text-[12px] text-gray-500 hover:text-indigo-600"
          >
            Friend code: <span className="font-mono font-bold">{friendCode}</span> (copy)
          </button>
        )}
      </div>

      <div className="flex gap-2 mb-4">
        <button onClick={() => setTab('activity')} className={`flex-1 py-2 rounded-xl text-xs font-bold ${tab === 'activity' ? 'bg-indigo-600 text-white' : 'bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 text-gray-500'}`}>ACTIVITY</button>
        <button onClick={() => setTab('settings')} className={`flex-1 py-2 rounded-xl text-xs font-bold ${tab === 'settings' ? 'bg-indigo-600 text-white' : 'bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 text-gray-500'}`}>SETTINGS</button>
      </div>

      {tab === 'activity' ? (
        <div className="space-y-2">
          {uploads.map((n) => (
            <a key={n.id} href={`/note?id=${n.id}`} className="block bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4">
              <div className="font-medium text-sm text-gray-900 dark:text-white">{n.title}</div>
              {n.created_at && <div className="text-xs text-gray-500 mt-1">{new Date(n.created_at).toLocaleDateString()}</div>}
            </a>
          ))}
          {uploads.length === 0 && <div className="text-center py-12 text-gray-400 text-sm">No uploads yet.</div>}
        </div>
      ) : (
        <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-5 space-y-4">
          <div>
            <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Full name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Bio</label>
            <input value={bio} onChange={(e) => setBio(e.target.value)} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600 dark:text-gray-300">Year level</label>
            <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white">
              {[1, 2, 3, 4].map((y) => <option key={y} value={y}>Year {y}</option>)}
            </select>
          </div>
          {msg && <p className="text-sm text-indigo-600">{msg}</p>}
          <button onClick={save} disabled={saving} className="w-full py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold disabled:opacity-50">
            {saving ? 'Saving…' : 'Save Profile'}
          </button>
          <a href="/settings" className="block text-center text-sm text-gray-500 hover:text-indigo-600">More settings</a>
          <button onClick={async () => { await signOut(); window.location.href = '/' }} className="w-full py-3 text-red-600 font-bold text-sm">
            Sign Out
          </button>
        </div>
      )}
    </AppShell>
  )
}
