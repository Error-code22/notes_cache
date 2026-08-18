'use client'

import { useEffect, useRef, useState } from 'react'

const NOTESY_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`

type ChatMsg = { role: 'user' | 'assistant'; content: string }

const GUEST_LIMIT = 3
const storageKey = 'notesy_web_history'

export default function ChatPage() {
  const [msgs, setMsgs] = useState<ChatMsg[]>([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const scrollRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    try {
      const raw = localStorage.getItem(storageKey)
      if (raw) setMsgs(JSON.parse(raw))
    } catch { /* ignore */ }
  }, [])

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
  }, [msgs, loading])

  const used = msgs.filter((m) => m.role === 'user').length
  const limitReached = used >= GUEST_LIMIT

  async function send() {
    const text = input.trim()
    if (!text || loading || limitReached) return
    const next = [...msgs, { role: 'user' as const, content: text }]
    setMsgs(next)
    setInput('')
    setLoading(true)
    try {
      const res = await fetch(NOTESY_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: text, history: msgs.slice(-5) }),
      })
      const data = await res.json()
      const reply = data?.content || 'Sorry, Notesy hit a snag. Try again?'
      const final = [...next, { role: 'assistant' as const, content: reply }]
      setMsgs(final)
      try { localStorage.setItem(storageKey, JSON.stringify(final)) } catch { /* ignore */ }
    } catch (e) {
      setMsgs([...next, { role: 'assistant', content: 'Could not reach Notesy. Check your connection.' }])
      console.error(e)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b sticky top-0 z-20">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Notesy Memory Lab</div>
          <span className="px-2 py-0.5 rounded bg-violet-600/10 text-violet-600 text-[10px] font-bold">BETA</span>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 py-6">
        <div className="bg-violet-600/5 border border-violet-200 rounded-xl px-4 py-3 text-[13px] text-violet-700 mb-5">
          Notesy is in beta — answers can be imperfect. Double-check important info.
        </div>

        <div ref={scrollRef} className="bg-white border border-gray-200 rounded-2xl p-4 h-[55vh] overflow-y-auto space-y-2">
          {msgs.length === 0 && (
            <div className="text-center text-gray-400 text-sm py-16">
              <div className="text-4xl mb-3">🧠</div>
              Ask about your notes, homework, or any study topic.
            </div>
          )}
          {msgs.map((m, i) => (
            <div
              key={i}
              className={`max-w-[85%] px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap ${
                m.role === 'user'
                  ? 'ml-auto bg-indigo-600 text-white rounded-br-sm'
                  : 'bg-gray-100 border border-gray-200 rounded-bl-sm'
              }`}
            >
              {m.content}
            </div>
          ))}
          {loading && <div className="text-xs text-gray-400 px-1">Notesy is thinking…</div>}
        </div>

        <div className="mt-4">
          {limitReached ? (
            <div className="text-center text-sm text-gray-500 py-3 bg-white border border-gray-200 rounded-2xl">
              Demo limit reached.{' '}
              <a href="/downloads" className="text-indigo-600 font-medium">Get the app</a> for the full experience.
            </div>
          ) : (
            <div className="flex gap-2">
              <input
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') send() }}
                placeholder="Ask Notesy…"
                className="flex-1 px-4 py-3 rounded-full border border-gray-300 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
              />
              <button
                onClick={send}
                disabled={loading}
                className="px-5 py-3 bg-indigo-600 text-white rounded-full text-sm font-medium hover:bg-indigo-700 disabled:opacity-50 transition"
              >
                Send
              </button>
            </div>
          )}
        </div>
      </main>
    </div>
  )
}
