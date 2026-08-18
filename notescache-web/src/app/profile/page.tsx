'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { signOut, supabase, useAuth } from '../../lib/auth'

export default function ProfilePage() {
  const { user, profile, loading } = useAuth()
  const router = useRouter()
  const [name, setName] = useState(profile?.full_name || '')
  const [year, setYear] = useState(profile?.year_level || 1)
  const [bio, setBio] = useState(profile?.bio || '')
  const [saving, setSaving] = useState(false)
  const [msg, setMsg] = useState('')

  if (loading) return <Shell><div className="text-center py-20 text-gray-500">Loading…</div></Shell>

  if (!user) {
    return (
      <Shell>
        <div className="text-center py-20">
          <div className="text-5xl mb-4">👤</div>
          <h1 className="text-xl font-bold text-gray-900 mb-2">Sign in to see your profile</h1>
          <a href="/login" className="inline-block px-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition">Sign In</a>
        </div>
      </Shell>
    )
  }

  async function save() {
    if (!user) return
    setSaving(true)
    setMsg('')
    try {
      const { error } = await supabase.from('profiles').update({
        full_name: name.trim() || profile?.full_name,
        year_level: year,
        bio: bio.trim(),
      }).eq('id', user.id)
      if (error) throw new Error(error.message)
      setMsg('Profile updated!')
    } catch (e) {
      setMsg(e instanceof Error ? e.message : 'Failed to update.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Shell>
      <div className="bg-white border border-gray-200 rounded-3xl p-6">
        <div className="flex items-center gap-4 mb-6">
          {profile?.avatar_url ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={profile.avatar_url} alt="avatar" className="w-16 h-16 rounded-2xl object-cover" />
          ) : (
            <div className="w-16 h-16 rounded-2xl bg-indigo-600/10 flex items-center justify-center text-2xl">
              {(profile?.full_name || user.email || '?')[0].toUpperCase()}
            </div>
          )}
          <div>
            <div className="font-bold text-gray-900 text-lg">{profile?.full_name || 'Student'}</div>
            <div className="text-sm text-gray-500">{user.email}</div>
            <div className="text-[11px] text-indigo-600 font-semibold mt-1 uppercase">{(profile?.role || 'student').toUpperCase()}</div>
          </div>
        </div>

        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-gray-600">Full Name</label>
            <input value={name} onChange={(e) => setName(e.target.value)} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400" />
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600">Year Level</label>
            <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm">
              {[1, 2, 3, 4].map((y) => <option key={y} value={y}>Year {y}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600">Bio</label>
            <textarea value={bio} onChange={(e) => setBio(e.target.value)} rows={3} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 resize-none" />
          </div>
        </div>

        {msg && <p className={`text-sm mt-3 ${msg.startsWith('Profile') ? 'text-green-600' : 'text-red-600'}`}>{msg}</p>}

        <button onClick={save} disabled={saving} className="w-full mt-4 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50">
          {saving ? 'Saving…' : 'Save Changes'}
        </button>

        <button
          onClick={async () => { await signOut(); router.push('/') }}
          className="w-full mt-3 py-2.5 rounded-xl text-sm font-bold text-red-600 border border-red-200 hover:bg-red-50 transition"
        >
          Sign Out
        </button>
      </div>
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">My Profile</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-3xl mx-auto px-4 py-6">{children}</main>
    </div>
  )
}
