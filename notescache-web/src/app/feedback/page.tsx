'use client'

import { useState } from 'react'
import { supabase } from '../../lib/auth'

export default function FeedbackPage() {
  const [type, setType] = useState<'bug' | 'feature'>('bug')
  const [content, setContent] = useState('')
  const [sending, setSending] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState('')

  async function submit() {
    if (!content.trim()) { setError('Please describe your issue or idea.'); return }
    setError('')
    setSending(true)
    try {
      const { error } = await supabase.from('app_feedback').insert({
        type,
        content: content.trim(),
        user_id: null,
        status: 'open',
      })
      if (error) throw new Error(error.message)
      setDone(true)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not submit feedback.')
    } finally {
      setSending(false)
    }
  }

  if (done) {
    return (
      <Shell>
        <div className="text-center py-20">
          <div className="text-5xl mb-4">✅</div>
          <h1 className="text-xl font-bold text-gray-900 mb-2">Thank you!</h1>
          <p className="text-sm text-gray-500 mb-6">Your feedback helps make NotesCache better.</p>
          <a href="/" className="text-sm text-indigo-600 font-medium hover:underline">← Back to home</a>
        </div>
      </Shell>
    )
  }

  return (
    <Shell>
      <h1 className="text-xl font-bold text-gray-900 mb-1">Feedback</h1>
      <p className="text-sm text-gray-500 mb-6">Report a bug or suggest a feature — it goes straight to the team.</p>

      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setType('bug')}
          className={`px-4 py-2 rounded-full text-sm font-medium border transition ${type === 'bug' ? 'bg-red-600 text-white border-red-600' : 'bg-white text-gray-600 border-gray-300'}`}
        >
          🐞 Bug Report
        </button>
        <button
          onClick={() => setType('feature')}
          className={`px-4 py-2 rounded-full text-sm font-medium border transition ${type === 'feature' ? 'bg-blue-600 text-white border-blue-600' : 'bg-white text-gray-600 border-gray-300'}`}
        >
          💡 New Feature
        </button>
      </div>

      <textarea
        value={content}
        onChange={(e) => setContent(e.target.value)}
        rows={5}
        placeholder={type === 'bug' ? "What went wrong? What did you expect?" : "Describe the feature you'd like…"}
        className="w-full px-4 py-3 rounded-2xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400 resize-none"
      />

      {error && <p className="text-sm text-red-600 mt-3">{error}</p>}

      <button
        onClick={submit}
        disabled={sending}
        className="w-full mt-4 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50"
      >
        {sending ? 'Sending…' : 'Submit Feedback'}
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
          <div className="font-bold text-gray-900">NotesCache</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-3xl mx-auto px-4 py-6">{children}</main>
    </div>
  )
}
