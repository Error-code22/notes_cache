'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@supabase/supabase-js'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
)

export default function Home() {
  const [showComms, setShowComms] = useState(true)

  useEffect(() => {
    (async () => {
      try {
        const { data } = await supabase.from('app_config').select('key, value')
        const row = (data || []).find((r: { key: string }) => r.key === 'show_comms_button')
        if (row && row.value === 'false') setShowComms(false)
      } catch { /* ignore */ }
    })()
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      {/* ── AppBar (app-like) ── */}
      <header className="bg-white border-b sticky top-0 z-20">
        <div className="max-w-3xl mx-auto px-5 h-16 flex items-center justify-between">
          <div>
            <div className="font-bold text-gray-900">Guest</div>
            <div className="text-[11px] text-gray-400 uppercase tracking-wide">Guest Mode</div>
          </div>
          <div className="flex items-center gap-2">
            <a
              href="/downloads"
              className="px-4 py-2 text-sm font-medium text-indigo-600 hover:text-indigo-800 transition"
            >
              Download App
            </a>
            <a
              href="/downloads"
              className="w-8 h-8 rounded-full bg-indigo-600/10 flex items-center justify-center"
              title="Account"
            >
              <span className="text-indigo-600 text-sm">👤</span>
            </a>
          </div>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-5 py-4">
        {/* ── Demo-mode banner (guests) ── */}
        <div className="bg-amber-500 text-white rounded-xl px-4 py-2.5 flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <span>ℹ️</span>
            <span className="text-[13px] font-medium">Demo mode: browsing only. Get the app for full access.</span>
          </div>
          <a href="/downloads" className="text-[12px] font-bold underline">SIGN IN</a>
        </div>

        {/* ── Hub cards (app replica) ── */}
        <div className="space-y-4">
          <a
            href="/notes"
            className="flex items-center gap-5 bg-white rounded-3xl border border-gray-100 p-6 hover:shadow-md hover:border-blue-300 transition"
          >
            <div className="p-4 rounded-2xl bg-blue-600/10">
              <span className="text-3xl">📚</span>
            </div>
            <div className="flex-1">
              <div className="font-bold text-gray-900 text-lg">Academic Notes</div>
              <div className="text-[13px] text-gray-500">Browse and read the shared library</div>
            </div>
            <span className="text-gray-300">›</span>
          </a>

          <a
            href="/downloads"
            className="flex items-center gap-5 bg-white rounded-3xl border border-gray-100 p-6 hover:shadow-md hover:border-pink-300 transition"
          >
            <div className="p-4 rounded-2xl bg-pink-600/10">
              <span className="text-3xl">❤️</span>
            </div>
            <div className="flex-1">
              <div className="font-bold text-gray-900 text-lg">Donate Notes</div>
              <div className="text-[13px] text-gray-500">Share notes with everyone on the app</div>
            </div>
            <span className="text-gray-300">›</span>
          </a>

          {showComms && (
            <a
              href="/downloads"
              className="flex items-center gap-5 bg-white rounded-3xl border border-gray-100 p-6 hover:shadow-md hover:border-orange-300 transition"
            >
              <div className="p-4 rounded-2xl bg-orange-600/10">
                <span className="text-3xl">💬</span>
              </div>
              <div className="flex-1">
                <div className="font-bold text-gray-900 text-lg">Communication</div>
                <div className="text-[13px] text-gray-500">Chat with friends and study groups</div>
              </div>
              <span className="text-gray-300">›</span>
            </a>
          )}

          <a
            href="/chat"
            className="flex items-center gap-5 bg-white rounded-3xl border border-violet-200 p-6 hover:shadow-md hover:border-violet-300 transition"
          >
            <div className="p-4 rounded-2xl bg-violet-600/10">
              <span className="text-3xl">🧠</span>
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <div className="font-bold text-gray-900 text-lg">Notesy Memory Lab</div>
                <span className="px-2 py-0.5 rounded bg-amber-500/15 text-amber-500 text-[10px] font-black">NEW</span>
              </div>
              <div className="text-[13px] text-gray-500">Quizzes, flashcards & memory tools</div>
            </div>
            <span className="text-gray-300">›</span>
          </a>

          {/* ── What's Coming ── */}
          <a
            href="/whats-coming"
            className="flex items-center gap-4 bg-white rounded-3xl border border-gray-100 p-5 hover:shadow-md hover:border-indigo-300 transition"
          >
            <div className="p-3 rounded-2xl bg-indigo-600/10">
              <span className="text-xl">🚧</span>
            </div>
            <div className="flex-1">
              <div className="font-semibold text-gray-900">What's Coming</div>
              <div className="text-[12px] text-gray-500">See upcoming features</div>
            </div>
            <span className="text-gray-300">›</span>
          </a>
        </div>
      </main>
    </div>
  )
}
