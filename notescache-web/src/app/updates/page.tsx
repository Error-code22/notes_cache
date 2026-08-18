'use client'

import { useEffect, useState } from 'react'
import { supabase } from '../../lib/auth'

type Update = { id: string; title: string; content: string; created_at: string }

export default function UpdatesPage() {
  const [items, setItems] = useState<Update[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    (async () => {
      try {
        const { data } = await supabase
          .from('app_updates')
          .select('id, title, content, created_at')
          .order('created_at', { ascending: false })
          .limit(30)
        setItems((data as Update[]) || [])
      } catch { /* ignore */ }
      setLoading(false)
    })()
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Updates</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-3xl mx-auto px-4 py-6">
        <h1 className="text-xl font-bold text-gray-900 mb-5">Announcements</h1>
        {loading ? (
          <div className="text-center py-16 text-gray-500">Loading…</div>
        ) : items.length === 0 ? (
          <div className="text-center py-16 text-gray-500">No announcements yet.</div>
        ) : (
          <div className="space-y-4">
            {items.map((u) => (
              <div key={u.id} className="bg-white border border-gray-200 rounded-2xl p-5">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-lg">📣</span>
                  <div className="font-semibold text-gray-900">{u.title}</div>
                </div>
                <p className="text-sm text-gray-600 whitespace-pre-wrap">{u.content}</p>
                <div className="text-xs text-gray-400 mt-3">
                  {new Date(u.created_at).toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })}
                </div>
              </div>
            ))}
          </div>
        )}
      </main>
    </div>
  )
}
