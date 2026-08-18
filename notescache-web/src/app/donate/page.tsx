'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { supabase, useAuth } from '../../lib/auth'

export default function DonatePage() {
  const { user, profile, loading } = useAuth()
  const router = useRouter()

  const [file, setFile] = useState<File | null>(null)
  const [title, setTitle] = useState('')
  const [year, setYear] = useState(1)
  const [semester, setSemester] = useState(1)
  const [uploading, setUploading] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  if (loading) return <Shell><div className="text-center py-20 text-gray-500">Loading…</div></Shell>

  if (!user) {
    return (
      <Shell>
        <div className="text-center py-20">
          <div className="text-5xl mb-4">🔒</div>
          <h1 className="text-xl font-bold text-gray-900 mb-2">Sign in to donate notes</h1>
          <p className="text-sm text-gray-500 mb-6">Uploading shares your notes with everyone on the app.</p>
          <a href="/login" className="inline-block px-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition">
            Sign In
          </a>
        </div>
      </Shell>
    )
  }

  async function upload() {
    setError('')
    if (!file) { setError('Pick a file first.'); return }
    if (!title.trim()) { setError('Enter a title for the note.'); return }
    if (!user) { setError('Not signed in.'); return }
    setUploading(true)
    try {
      const session = await supabase.auth.getSession()
      const token = session.data.session?.access_token
      if (!token) throw new Error('Not signed in')

      const fd = new FormData()
      fd.append('file', file)
      fd.append('folder', 'notes')
      fd.append('userId', user.id)

      const res = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/cloudinary-upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! },
        body: fd,
      })
      const data = await res.json()
      if (!res.ok || data.success !== true) {
        throw new Error(data.error || 'Upload failed')
      }

      const { error: dbErr } = await supabase.from('notes').insert({
        title: title.trim(),
        lecturer_name: profile?.full_name || 'Student Upload',
        target_year: year,
        semester,
        gdrive_id: data.url,
        content: '',
        category: 'Note',
        file_size: file.size,
        user_id: user.id,
        telegram_msg_id: data.telegramMsgId ?? null,
        telegram_file_id: data.telegramFileId ?? null,
      })
      if (dbErr) throw new Error(dbErr.message)
      setDone(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Upload failed.')
    } finally {
      setUploading(false)
    }
  }

  if (done) {
    return (
      <Shell>
        <div className="text-center py-20">
          <div className="text-5xl mb-4">🎉</div>
          <h1 className="text-xl font-bold text-gray-900 mb-2">Note shared!</h1>
          <p className="text-sm text-gray-500 mb-6">Thanks for contributing to the library.</p>
          <a href="/notes" className="text-sm text-indigo-600 font-medium hover:underline">Browse the library →</a>
        </div>
      </Shell>
    )
  }

  return (
    <Shell>
      <h1 className="text-xl font-bold text-gray-900 mb-1">Donate Notes</h1>
      <p className="text-sm text-gray-500 mb-6">Share notes with everyone on the app.</p>

      <div className="bg-white border border-gray-200 rounded-2xl p-5 space-y-4">
        <div>
          <label className="text-xs font-semibold text-gray-600">File</label>
          <input
            type="file"
            onChange={(e) => setFile(e.target.files?.[0] || null)}
            className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm"
          />
          {file && <div className="text-xs text-gray-500 mt-1">{file.name} ({(file.size / 1024 / 1024).toFixed(1)} MB)</div>}
        </div>
        <div>
          <label className="text-xs font-semibold text-gray-600">Title</label>
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="e.g. Thermodynamics Lecture 4.pdf"
            className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="text-xs font-semibold text-gray-600">Year</label>
            <select value={year} onChange={(e) => setYear(Number(e.target.value))} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm">
              {[1, 2, 3, 4].map((y) => <option key={y} value={y}>Year {y}</option>)}
            </select>
          </div>
          <div>
            <label className="text-xs font-semibold text-gray-600">Semester</label>
            <select value={semester} onChange={(e) => setSemester(Number(e.target.value))} className="w-full mt-1 px-3 py-2 rounded-xl border border-gray-300 text-sm">
              <option value={1}>Semester 1</option>
              <option value={2}>Semester 2</option>
            </select>
          </div>
        </div>
      </div>

      {error && <p className="text-sm text-red-600 mt-3">{error}</p>}

      <button
        onClick={upload}
        disabled={uploading}
        className="w-full mt-4 py-3 bg-pink-600 text-white rounded-xl text-sm font-bold hover:bg-pink-700 transition disabled:opacity-50"
      >
        {uploading ? 'Uploading…' : 'Share Note'}
      </button>
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Donate Notes</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-3xl mx-auto px-4 py-6">{children}</main>
    </div>
  )
}
