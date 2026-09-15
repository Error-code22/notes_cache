'use client'

import { useCallback, useEffect, useMemo, useState } from 'react'
import { useAuth, supabase } from '../../lib/auth'
import AppShell from '../../components/AppShell'
import { SendIcon, ChatIcon, GroupIcon } from '../../components/icons'

type Room = {
  id: string
  name: string
  is_group: boolean
  is_public?: boolean
  member_ids: string[]
  last_message?: string
  last_message_time?: string
  description?: string
  created_by?: string
}

type Msg = {
  id: string
  room_id: string
  sender_id: string
  sender_name?: string
  content: string
  created_at?: string
}

export default function CommunicationPage() {
  const { user, loading } = useAuth()
  const [rooms, setRooms] = useState<Room[]>([])
  const [publicRooms, setPublicRooms] = useState<Room[]>([])
  const [friends, setFriends] = useState<{ id: string; full_name?: string }[]>([])
  const [active, setActive] = useState<Room | null>(null)
  const [messages, setMessages] = useState<Msg[]>([])
  const [input, setInput] = useState('')
  const [tab, setTab] = useState<'groups' | 'chats'>('chats')
  const [friendCode, setFriendCode] = useState('')
  const [myCode, setMyCode] = useState('')
  const [showCode, setShowCode] = useState(false)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')

  const memberNames = useMemo(() => {
    const map: Record<string, string> = {}
    friends.forEach((f) => { map[f.id] = f.full_name || 'User' })
    if (user) map[user.id] = 'You'
    return map
  }, [friends, user])

  const load = useCallback(async () => {
    if (!user) return
    const [{ data: roomData }, { data: pub }, { data: profile }] = await Promise.all([
      supabase.from('chat_rooms').select('*').order('last_message_time', { ascending: false }),
      supabase.from('chat_rooms').select('*').eq('is_public', true).eq('is_group', true),
      supabase.from('profiles').select('id, full_name, friend_code').eq('id', user.id).maybeSingle(),
    ])
    const mine = ((roomData as Room[]) || []).filter((r) => (r.member_ids || []).includes(user.id))
    setRooms(mine)
    setPublicRooms(((pub as Room[]) || []).filter((r) => !(r.member_ids || []).includes(user.id)))
    setMyCode((profile as { friend_code?: string })?.friend_code || '')
    const ids = Array.from(new Set(mine.flatMap((r) => r.member_ids || [])))
    if (ids.length) {
      const { data: profs } = await supabase.from('profiles').select('id, full_name').in('id', ids)
      setFriends((profs as { id: string; full_name?: string }[]) || [])
    }
  }, [user])

  useEffect(() => {
    if (user) load()
  }, [user, load])

  useEffect(() => {
    if (!active) return
    let cancelled = false
    const loadMsgs = async () => {
      const { data } = await supabase
        .from('chat_messages')
        .select('*')
        .eq('room_id', active.id)
        .order('created_at', { ascending: true })
        .limit(200)
      if (!cancelled) setMessages((data as Msg[]) || [])
    }
    loadMsgs()
    const channel = supabase
      .channel(`room-${active.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `room_id=eq.${active.id}` }, (payload) => {
        setMessages((m) => [...m, payload.new as Msg])
      })
      .subscribe()
    return () => { cancelled = true; supabase.removeChannel(channel) }
  }, [active])

  async function send() {
    if (!user || !active || !input.trim()) return
    const content = input.trim()
    setInput('')
    setBusy(true)
    try {
      const { error } = await supabase.from('chat_messages').insert({
        room_id: active.id,
        sender_id: user.id,
        content,
        sender_name: user.email?.split('@')[0] || 'You',
      })
      if (error) throw new Error(error.message)
      await supabase.from('chat_rooms').update({
        last_message: content,
        last_message_time: new Date().toISOString(),
      }).eq('id', active.id)
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Send failed')
    } finally {
      setBusy(false)
    }
  }

  async function addFriend() {
    if (!user) { window.location.href = '/login'; return }
    const code = friendCode.trim().toUpperCase()
    if (!code) return
    setErr('')
    const { data: found } = await supabase.from('profiles').select('id, full_name, friend_code').eq('friend_code', code).maybeSingle()
    if (!found) { setErr('No user with that friend code.'); return }
    const { error } = await supabase.from('friends').insert({ user_id: user.id, friend_id: found.id, status: 'accepted' })
    if (error && !error.message.includes('duplicate')) { setErr(error.message); return }
    setFriendCode('')
    load()
  }

  async function createGroup() {
    if (!user) { window.location.href = '/login'; return }
    const name = window.prompt('Group name')
    if (!name?.trim()) return
    const description = window.prompt('Description (optional)') || ''
    const isPublic = window.confirm('Make this a public group?') ? true : false
    const { data, error } = await supabase.from('chat_rooms').insert({
      name: name.trim(),
      is_group: true,
      is_public: isPublic,
      description,
      member_ids: [user.id],
      created_by: user.id,
    }).select('*').single()
    if (error) { setErr(error.message); return }
    if (data) { setRooms((r) => [data as Room, ...r]); setActive(data as Room) }
  }

  async function joinPublic(room: Room) {
    if (!user) { window.location.href = '/login'; return }
    const members = Array.from(new Set([...(room.member_ids || []), user.id]))
    const { error } = await supabase.from('chat_rooms').update({ member_ids: members }).eq('id', room.id)
    if (error) { setErr(error.message); return }
    load()
  }

  if (loading) return <AppShell title="Communication"><div className="text-center py-16 text-gray-400">Loading…</div></AppShell>
  if (!user) {
    return (
      <AppShell title="Communication">
        <div className="text-center py-20">
          <div className="flex justify-center mb-4 text-gray-300"><ChatIcon size={48} /></div>
          <h1 className="text-xl font-bold text-gray-900 dark:text-white mb-2">Sign in to chat</h1>
          <a href="/login" className="inline-block px-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold">Sign In</a>
        </div>
      </AppShell>
    )
  }

  if (active) {
    return (
      <AppShell title={active.name || 'Chat'} backHref="#" action={
        <button onClick={() => setActive(null)} className="text-xs font-bold text-indigo-600 shrink-0">LIST</button>
      }>
        <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-3 h-[60vh] overflow-y-auto space-y-2 mb-3">
          {messages.length === 0 && <div className="text-center text-gray-400 text-sm py-16">No messages yet. Say hi!</div>}
          {messages.map((m) => {
            const mine = m.sender_id === user.id
            return (
              <div key={m.id} className={`max-w-[85%] ${mine ? 'ml-auto' : ''}`}>
                {!mine && active.is_group && (
                  <div className="text-[10px] text-gray-400 mb-0.5 px-1">{m.sender_name || memberNames[m.sender_id] || 'User'}</div>
                )}
                <div className={`px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap ${mine ? 'bg-indigo-600 text-white rounded-br-sm' : 'bg-gray-100 dark:bg-white/5 border border-gray-200 dark:border-white/10 text-gray-900 dark:text-gray-100 rounded-bl-sm'}`}>
                  {m.content}
                </div>
              </div>
            )
          })}
        </div>
        <div className="flex gap-2">
          <input
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') send() }}
            placeholder="Message…"
            className="flex-1 px-4 py-3 rounded-full border border-gray-300 dark:border-white/15 bg-white dark:bg-[#1C1C1E] text-sm text-gray-900 dark:text-white"
          />
          <button onClick={send} disabled={busy} className="p-3 bg-indigo-600 text-white rounded-full disabled:opacity-50">
            <SendIcon size={18} />
          </button>
        </div>
      </AppShell>
    )
  }

  const dmRooms = rooms.filter((r) => !r.is_group)

  return (
    <AppShell title="Communication">
      <div className="flex items-center gap-2 mb-4 flex-wrap">
        <div className="flex-1 min-w-[160px] bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl px-3 py-2">
          <div className="text-[10px] text-gray-400 font-bold">MY CODE</div>
          <button onClick={() => { setShowCode(true); navigator.clipboard?.writeText(myCode) }} className="text-sm font-mono font-bold text-gray-900 dark:text-white">
            {showCode || !myCode ? (myCode || '—') : '•••-•••'}
          </button>
        </div>
        <button onClick={createGroup} className="px-3 py-2 rounded-2xl bg-indigo-600 text-white text-xs font-bold">
          + Group
        </button>
      </div>

      <div className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-3 mb-4 flex gap-2">
        <input
          value={friendCode}
          onChange={(e) => setFriendCode(e.target.value)}
          placeholder="Friend code (ABC-123)"
          className="flex-1 px-3 py-2 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
        />
        <button onClick={addFriend} className="px-3 py-2 rounded-xl bg-emerald-600 text-white text-xs font-bold">Add Friend</button>
      </div>

      {err && <p className="text-sm text-red-600 mb-3">{err}</p>}

      <div className="flex gap-2 mb-4">
        <Tab active={tab === 'chats'} onClick={() => setTab('chats')}>CHATS</Tab>
        <Tab active={tab === 'groups'} onClick={() => setTab('groups')}>GROUPS</Tab>
      </div>

      {tab === 'chats' ? (
        <div className="space-y-2">
          {dmRooms.length === 0 && (
            <div className="text-center py-12 text-gray-400 text-sm">No DMs yet. Add a friend by code.</div>
          )}
          {dmRooms.map((r) => (
            <button key={r.id} onClick={() => setActive(r)} className="w-full text-left bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 hover:border-indigo-300 transition flex items-center gap-3">
              <div className="w-10 h-10 rounded-full bg-indigo-600/10 flex items-center justify-center text-indigo-600 shrink-0">
                <ChatIcon size={20} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-gray-900 dark:text-white text-sm truncate">{r.name}</div>
                <div className="text-xs text-gray-500 truncate">{r.last_message || 'No messages'}</div>
              </div>
            </button>
          ))}
        </div>
      ) : (
        <div className="space-y-4">
          <div>
            <div className="text-[11px] font-bold text-gray-400 mb-2">MY GROUPS</div>
            <div className="space-y-2">
              {rooms.filter((r) => r.is_group).map((r) => (
                <button key={r.id} onClick={() => setActive(r)} className="w-full text-left bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 hover:border-indigo-300 transition flex items-center gap-3">
                  <div className="w-10 h-10 rounded-xl bg-orange-500/10 flex items-center justify-center text-orange-500 shrink-0">
                    <GroupIcon size={20} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-gray-900 dark:text-white text-sm truncate">{r.name}</div>
                    <div className="text-xs text-gray-500">{(r.member_ids || []).length} members</div>
                  </div>
                </button>
              ))}
              {rooms.filter((r) => r.is_group).length === 0 && (
                <div className="text-sm text-gray-400 py-4">You haven&apos;t joined any groups.</div>
              )}
            </div>
          </div>
          <div>
            <div className="text-[11px] font-bold text-gray-400 mb-2">PUBLIC GROUPS</div>
            <div className="space-y-2">
              {publicRooms.map((r) => (
                <div key={r.id} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-4 flex items-center gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="font-semibold text-gray-900 dark:text-white text-sm">{r.name}</div>
                    <div className="text-xs text-gray-500 truncate">{r.description || `${(r.member_ids || []).length} members`}</div>
                  </div>
                  <button onClick={() => joinPublic(r)} className="px-3 py-1.5 rounded-xl bg-indigo-600 text-white text-xs font-bold">Join</button>
                </div>
              ))}
              {publicRooms.length === 0 && <div className="text-sm text-gray-400 py-4">No public groups right now.</div>}
            </div>
          </div>
        </div>
      )}
    </AppShell>
  )
}

function Tab({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      className={`flex-1 py-2 rounded-xl text-xs font-bold transition ${active ? 'bg-indigo-600 text-white' : 'bg-white dark:bg-[#1C1C1E] text-gray-500 border border-gray-200 dark:border-white/10'}`}
    >
      {children}
    </button>
  )
}
