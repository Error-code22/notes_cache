'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../../lib/auth'
import { supabase } from '../../lib/auth'
import { fileToBase64, renderMarkdownLite, todayKey } from '../../lib/utils'
import {
  ArrowBackIcon, BrainIcon, SendIcon, AttachIcon, ShieldIcon, ListIcon,
} from '../../components/icons'

type ChatMsg = { role: 'user' | 'assistant'; content: string; images?: string[] }

type Conversation = {
  id: number
  title: string
  pinned: boolean
  locked: boolean
  created_at: string
  updated_at: string
}

const NOTESY_URL = `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/notesy`
const GUEST_LIMIT = 3
const USER_DAILY_LIMIT = 20
const MAX_IMAGES = 3

function prefKey(userId: string) {
  return `notesy_daily_${userId}_${todayKey()}`
}

export default function ChatPage() {
  const { user, profile, loading: authLoading } = useAuth()
  const isGuest = !user
  const isAdmin = String(profile?.role || '').toLowerCase().includes('admin')

  const [msgs, setMsgs] = useState<ChatMsg[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [drawerOpen, setDrawerOpen] = useState(false)
  const [convs, setConvs] = useState<Conversation[]>([])
  const [currentId, setCurrentId] = useState<number | null>(null)
  const [pendingImages, setPendingImages] = useState<string[]>([])
  const [privateStudy, setPrivateStudy] = useState(false)
  const [vaultLocked, setVaultLocked] = useState(false)
  const [vaultConv, setVaultConv] = useState(false)
  const [betaSeen, setBetaSeen] = useState(true)
  const [used, setUsed] = useState(0)
  const scrollRef = useRef<HTMLDivElement>(null)
  const fileRef = useRef<HTMLInputElement>(null)
  const imgRef = useRef<HTMLInputElement>(null)
  const renameId = useRef<number | null>(null)

  const limitReached = isGuest ? used >= GUEST_LIMIT : (!isAdmin && used >= USER_DAILY_LIMIT)

  // Guest local history + daily count
  useEffect(() => {
    if (isGuest) {
      try {
        const raw = localStorage.getItem('guest_ai_history')
        if (raw) setMsgs(JSON.parse(raw))
        const n = Number(localStorage.getItem(`guest_ai_messages_${todayKey()}`) || '0')
        setUsed(n)
      } catch { /* ignore */ }
    } else if (user) {
      const n = Number(localStorage.getItem(prefKey(user.id)) || '0')
      setUsed(n)
      if (!localStorage.getItem('notesy_beta_notice_shown')) setBetaSeen(false)
    }
  }, [isGuest, user])

  const loadConvs = useCallback(async () => {
    if (!user) return
    const { data } = await supabase
      .from('ai_conversations')
      .select('id,title,pinned,locked,created_at,updated_at')
      .eq('user_id', user.id)
      .order('pinned', { ascending: false })
      .order('updated_at', { ascending: false })
    let list = (data as Conversation[]) || []
    if (list.length === 0) {
      const { data: created } = await supabase
        .from('ai_conversations')
        .insert({ user_id: user.id, title: 'New chat' })
        .select('id,title,pinned,locked,created_at,updated_at')
        .single()
      if (created) list = [created as Conversation]
    }
    setConvs(list)
    if (list[0]) await openConv(list[0])
  }, [user])

  useEffect(() => {
    if (user) loadConvs()
  }, [user, loadConvs])

  useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight
  }, [msgs, busy])

  async function openConv(c: Conversation) {
    setCurrentId(c.id)
    setVaultConv(!!c.locked)
    setVaultLocked(false)
    setDrawerOpen(false)
    const { data } = await supabase
      .from('ai_messages')
      .select('role,content')
      .eq('conversation_id', c.id)
      .order('created_at', { ascending: true })
    setMsgs(((data as ChatMsg[]) || []).map((m) => ({ role: m.role as ChatMsg['role'], content: m.content })))
  }

  async function newConv() {
    if (!user) {
      setMsgs([])
      setCurrentId(null)
      setVaultConv(false)
      setDrawerOpen(false)
      return
    }
    const { data } = await supabase
      .from('ai_conversations')
      .insert({ user_id: user.id, title: 'New chat' })
      .select('id,title,pinned,locked,created_at,updated_at')
      .single()
    if (data) {
      await loadConvs()
      await openConv(data as Conversation)
    }
  }

  async function persistGuest(next: ChatMsg[]) {
    try { localStorage.setItem('guest_ai_history', JSON.stringify(next)) } catch { /* ignore */ }
  }

  async function bumpCount() {
    if (isGuest) {
      const k = `guest_ai_messages_${todayKey()}`
      const n = Number(localStorage.getItem(k) || '0') + 1
      localStorage.setItem(k, String(n))
      setUsed(n)
    } else if (user) {
      const k = prefKey(user.id)
      const n = Number(localStorage.getItem(k) || '0') + 1
      localStorage.setItem(k, String(n))
      setUsed(n)
    }
  }

  async function send() {
    const text = input.trim()
    if ((!text && pendingImages.length === 0) || busy || limitReached) return
    if (vaultLocked) return

    const userMsg: ChatMsg = {
      role: 'user',
      content: text || (pendingImages.length ? `Analyze these ${pendingImages.length} image(s).` : ''),
      images: pendingImages.length ? [...pendingImages] : undefined,
    }
    const next = [...msgs, userMsg]
    setMsgs(next)
    setInput('')
    setPendingImages([])
    setBusy(true)

    const history = msgs
      .filter((m) => m.role === 'assistant' || m.role === 'user')
      .slice(-12)
      .map((m) => ({ role: m.role, content: m.content }))

    try {
      const body: Record<string, unknown> = {
        message: userMsg.content,
        history,
        userId: user?.id || 'guest_user',
      }
      if (userMsg.images?.length === 1) body.imageBase64 = userMsg.images[0]
      if (userMsg.images && userMsg.images.length > 1) body.imageBase64s = userMsg.images

      const res = await fetch(NOTESY_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(user ? { Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token}` } : {}),
        },
        body: JSON.stringify(body),
      })
      const data = await res.json()
      const reply = data?.content || data?.error || 'Sorry, Notesy hit a snag. Try again?'
      const final: ChatMsg[] = [...next, { role: 'assistant', content: reply }]
      setMsgs(final)
      await bumpCount()

      if (isGuest) await persistGuest(final)
      else if (user && currentId) {
        await supabase.from('ai_messages').insert([
          { conversation_id: currentId, user_id: user.id, role: 'user', content: userMsg.content },
          { conversation_id: currentId, user_id: user.id, role: 'assistant', content: reply },
        ])
        await supabase.from('ai_conversations').update({ updated_at: new Date().toISOString() }).eq('id', currentId)
        if (msgs.length === 0) {
          const title = (text || 'Image chat').slice(0, 40)
          await supabase.from('ai_conversations').update({ title }).eq('id', currentId)
          setConvs((cs) => cs.map((c) => (c.id === currentId ? { ...c, title } : c)))
        }
      }
    } catch (e) {
      console.error(e)
      setMsgs([...next, { role: 'assistant', content: 'Could not reach Notesy. Check your connection.' }])
    } finally {
      setBusy(false)
    }
  }

  async function onPickImages(files: FileList | null) {
    if (!files?.length) return
    const room = MAX_IMAGES - pendingImages.length
    if (room <= 0) return
    const picked = Array.from(files).slice(0, room)
    const b64s: string[] = []
    for (const f of picked) {
      if (!f.type.startsWith('image/')) continue
      b64s.push(await fileToBase64(f))
    }
    setPendingImages((p) => [...p, ...b64s].slice(0, MAX_IMAGES))
  }

  async function onPickText(file: FileList | null) {
    const f = file?.[0]
    if (!f) return
    const text = await f.text()
    setInput((t) => (t ? `${t}\n\n${text}` : text).slice(0, 8000))
  }

  function confirmBeta() {
    localStorage.setItem('notesy_beta_notice_shown', '1')
    setBetaSeen(true)
  }

  if (authLoading) {
    return <div className="min-h-screen bg-[#FAFAF7] dark:bg-[#121212] flex items-center justify-center text-gray-400">Loading…</div>
  }

  return (
    <div className="min-h-screen bg-[#FAFAF7] dark:bg-[#121212] flex flex-col">
      <header className="sticky top-0 z-20 bg-white/95 dark:bg-[#1C1C1E]/95 backdrop-blur border-b border-black/5 dark:border-white/10">
        <div className="max-w-3xl mx-auto px-3 h-14 flex items-center gap-2">
          <a href="/" className="text-gray-400 hover:text-indigo-600 flex items-center p-1"><ArrowBackIcon size={22} /></a>
          {!isGuest && (
            <button onClick={() => setDrawerOpen(true)} className="p-2 text-gray-500 hover:text-indigo-600" title="Conversations">
              <ListIcon size={22} />
            </button>
          )}
          <div className="font-bold text-gray-900 dark:text-white">Notesy</div>
          <span className="px-2 py-0.5 rounded bg-violet-600/10 text-violet-600 dark:text-violet-400 text-[10px] font-bold">BETA</span>
          <div className="flex-1" />
          <button
            onClick={() => setPrivateStudy((v) => !v)}
            className={`px-2 py-1 rounded-lg text-[11px] font-bold transition ${privateStudy ? 'bg-amber-500/15 text-amber-600' : 'text-gray-400 hover:text-amber-600'}`}
            title="Private study mode"
          >
            PRIVATE
          </button>
          <button
            onClick={() => {
              if (vaultConv) setVaultLocked((v) => !v)
            }}
            className={`p-2 rounded-lg transition ${vaultLocked ? 'text-red-500' : vaultConv ? 'text-violet-500' : 'text-gray-300'}`}
            title={vaultConv ? (vaultLocked ? 'Unlock vault (hold)' : 'Lock vault') : 'Vault (create a locked chat)'}
          >
            <ShieldIcon size={20} />
          </button>
        </div>
      </header>

      {privateStudy && (
        <div className="bg-amber-500/15 text-amber-700 dark:text-amber-300 text-[12px] px-4 py-2 text-center">
          Private study mode — this chat is not saved after you leave.
        </div>
      )}
      {vaultLocked && (
        <div className="bg-red-500/10 text-red-600 dark:text-red-300 text-[12px] px-4 py-2 text-center">
          Vault locked. Tap the shield to unlock.
        </div>
      )}
      {!isGuest && !isAdmin && limitReached && (
        <div className="bg-orange-500/15 text-orange-700 dark:text-orange-300 text-[12px] px-4 py-2 text-center">
          Daily message limit reached. Try again tomorrow.
        </div>
      )}

      <main className="flex-1 max-w-3xl w-full mx-auto px-4 py-4 flex flex-col min-h-0">
        {!betaSeen && (
          <div className="mb-4 bg-violet-600/10 border border-violet-300 dark:border-violet-500/30 rounded-2xl p-4">
            <div className="font-bold text-violet-800 dark:text-violet-200 mb-1">Notesy is in beta</div>
            <p className="text-[13px] text-violet-700 dark:text-violet-300 mb-3 leading-relaxed">
              Notesy can make mistakes. Always double-check important information with your course materials or lecturer.
            </p>
            <button onClick={confirmBeta} className="px-4 py-2 bg-violet-600 text-white rounded-xl text-sm font-bold">Got it</button>
          </div>
        )}

        <div ref={scrollRef} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 flex-1 min-h-[50vh] max-h-[65vh] overflow-y-auto space-y-3">
          {vaultLocked ? (
            <div className="text-center py-16 text-gray-400 text-sm">Vault is locked.</div>
          ) : msgs.length === 0 ? (
            <div className="text-center text-gray-400 dark:text-gray-500 text-sm py-16">
              <div className="flex justify-center mb-3 text-violet-400"><BrainIcon size={40} /></div>
              Ask about your notes, homework, or any study topic.
            </div>
          ) : (
            msgs.map((m, i) => (
              <div key={i} className={`max-w-[88%] ${m.role === 'user' ? 'ml-auto' : ''}`}>
                {m.images?.length ? (
                  <div className={`flex gap-1 mb-1 flex-wrap ${m.role === 'user' ? 'justify-end' : ''}`}>
                    {m.images.map((b64, j) => (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img key={j} src={`data:image/jpeg;base64,${b64}`} alt="" className="w-16 h-16 object-cover rounded-xl border border-black/10" />
                    ))}
                  </div>
                ) : null}
                {m.content ? (
                  <div
                    className={`px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap ${m.role === 'user' ? 'bg-indigo-600 text-white rounded-br-sm' : 'bg-gray-100 dark:bg-white/5 border border-gray-200 dark:border-white/10 text-gray-900 dark:text-gray-100 rounded-bl-sm prose-sm dark:prose-invert'}`}
                    dangerouslySetInnerHTML={m.role === 'assistant' ? { __html: renderMarkdownLite(m.content) } : undefined}
                  >
                    {m.role === 'user' ? m.content : undefined}
                  </div>
                ) : null}
              </div>
            ))
          )}
          {busy && <div className="text-xs text-gray-400 px-1">Notesy is thinking…</div>}
        </div>

        {pendingImages.length > 0 && (
          <div className="flex gap-2 mt-3 flex-wrap">
            {pendingImages.map((b64, i) => (
              <div key={i} className="relative">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`data:image/jpeg;base64,${b64}`} alt="" className="w-14 h-14 object-cover rounded-xl border" />
                <button
                  onClick={() => setPendingImages((p) => p.filter((_, j) => j !== i))}
                  className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-black/70 text-white text-xs"
                >×</button>
              </div>
            ))}
          </div>
        )}

        <div className="mt-4">
          {limitReached ? (
            <div className="text-center text-sm text-gray-500 dark:text-gray-400 py-3 bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl">
              {isGuest ? (
                <>Demo limit reached. <a href="/login" className="text-indigo-600 font-medium">Sign up</a> for the full experience.</>
              ) : (
                <>Daily limit reached. Come back tomorrow.</>
              )}
            </div>
          ) : vaultLocked ? (
            <div className="text-center text-sm text-gray-500 py-3">Unlock the vault to continue.</div>
          ) : (
            <div className="flex gap-2 items-end">
              <div className="flex flex-col gap-1">
                <button onClick={() => imgRef.current?.click()} className="text-gray-400 hover:text-indigo-600 p-2" title="Attach images">
                  <AttachIcon size={22} />
                </button>
                <input ref={imgRef} type="file" accept="image/*" multiple hidden onChange={(e) => onPickImages(e.target.files)} />
                <input ref={fileRef} type="file" accept=".txt,.md,.js,.ts,.py,.dart,.json,.csv" hidden onChange={(e) => onPickText(e.target.files)} />
              </div>
              <textarea
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send() } }}
                placeholder="Ask Notesy…"
                rows={1}
                className="flex-1 px-4 py-3 rounded-2xl border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white resize-none focus:outline-none focus:ring-2 focus:ring-indigo-400"
              />
              <button onClick={send} disabled={busy} className="p-3 bg-indigo-600 text-white rounded-full hover:bg-indigo-700 disabled:opacity-50 transition">
                <SendIcon size={18} />
              </button>
            </div>
          )}
        </div>
      </main>

      {/* Conversations drawer */}
      {drawerOpen && !isGuest && (
        <div className="fixed inset-0 z-40 bg-black/40" onClick={() => setDrawerOpen(false)}>
          <aside
            className="absolute left-0 top-0 h-full w-80 max-w-[90vw] bg-white dark:bg-[#1C1C1E] shadow-xl p-4 overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-4">
              <div className="font-bold text-gray-900 dark:text-white">Chats</div>
              <button onClick={newConv} className="px-3 py-1.5 bg-indigo-600 text-white rounded-xl text-sm font-bold">+ New</button>
            </div>
            {(['Chats', 'Private'] as const).map((section) => {
              const list = convs.filter((c) => (section === 'Private' ? c.locked : !c.locked))
              if (!list.length) return null
              return (
                <div key={section} className="mb-4">
                  <div className="text-[11px] font-bold text-gray-400 uppercase tracking-wide mb-2">{section}</div>
                  <div className="space-y-1">
                    {list.map((c) => (
                      <div
                        key={c.id}
                        className={`w-full text-left px-3 py-2.5 rounded-xl text-sm transition ${currentId === c.id ? 'bg-indigo-600/10 text-indigo-700 dark:text-indigo-300' : 'hover:bg-black/5 dark:hover:bg-white/5 text-gray-800 dark:text-gray-100'}`}
                      >
                        <button className="w-full text-left" onClick={() => openConv(c)}>
                          <div className="font-medium truncate">{c.pinned ? '📌 ' : ''}{c.title || 'Chat'}</div>
                        </button>
                        <div className="flex gap-2 mt-1 text-[11px]">
                          <button
                            className="text-gray-400 hover:text-indigo-600"
                            onClick={async () => {
                              await supabase.from('ai_conversations').update({ pinned: !c.pinned }).eq('id', c.id)
                              loadConvs()
                            }}
                          >{c.pinned ? 'Unpin' : 'Pin'}</button>
                          <button
                            className="text-gray-400 hover:text-indigo-600"
                            onClick={async () => {
                              const title = window.prompt('Rename chat', c.title)
                              if (title == null) return
                              await supabase.from('ai_conversations').update({ title }).eq('id', c.id)
                              loadConvs()
                            }}
                          >Rename</button>
                          <button
                            className="text-gray-400 hover:text-red-600"
                            onClick={async () => {
                              if (!window.confirm('Delete this chat?')) return
                              await supabase.from('ai_messages').delete().eq('conversation_id', c.id)
                              await supabase.from('ai_conversations').delete().eq('id', c.id)
                              if (currentId === c.id) { setMsgs([]); setCurrentId(null) }
                              loadConvs()
                            }}
                          >Delete</button>
                          <button
                            className="text-gray-400 hover:text-violet-600"
                            onClick={async () => {
                              await supabase.from('ai_conversations').update({ locked: !c.locked }).eq('id', c.id)
                              loadConvs()
                            }}
                          >{c.locked ? 'Unlock' : 'Vault'}</button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )
            })}
            <button onClick={() => setDrawerOpen(false)} className="w-full mt-2 py-2 text-sm text-gray-500">Close</button>
          </aside>
        </div>
      )}
    </div>
  )
}
