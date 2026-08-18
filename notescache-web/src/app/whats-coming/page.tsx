'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
)

type Item = { id: string; title: string; description?: string }

export default function WhatsComingPage() {
  const [items, setItems] = useState<Item[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    (async () => {
      try {
        const { data } = await supabase.from('roadmap_items').select('id, title, description').eq('active', true).order('sort_order')
        setItems((data as Item[]) || [])
      } catch { /* ignore */ }
      setLoading(false)
    })()
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b sticky top-0 z-20">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">What's Coming</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 py-6">
        <div className="bg-indigo-600/5 border border-indigo-200 rounded-xl px-4 py-3 text-[13px] text-indigo-700 mb-5">
          NotesCache is in active development. Here's what we're building — and you can suggest what's next!
        </div>

        {loading ? (
          <div className="text-center py-16 text-gray-500">Loading…</div>
        ) : items.length === 0 ? (
          <div className="text-center py-16 text-gray-500">Nothing planned yet.</div>
        ) : (
          <div className="space-y-3">
            {items.map((item) => (
              <div key={item.id} className="bg-white border border-gray-200 rounded-2xl p-5 flex gap-4">
                <div className="mt-1 w-2.5 h-2.5 rounded-full bg-indigo-500 shrink-0" />
                <div>
                  <div className="font-semibold text-gray-900">{item.title}</div>
                  {item.description ? <div className="text-sm text-gray-500 mt-0.5">{item.description}</div> : null}
                </div>
              </div>
            ))}
          </div>
        )}

        <a
          href="https://wa.me/254703300084?text=Feature%20request%20for%20NotesCache%3A"
          target="_blank"
          rel="noopener noreferrer"
          className="mt-6 block text-center px-5 py-3 bg-white border border-gray-300 rounded-2xl text-sm font-medium text-gray-700 hover:border-indigo-400 hover:text-indigo-600 transition"
        >
          💡 Request a feature
        </a>
      </main>
    </div>
  )
}
