'use client'

import { useCallback, useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase, useAuth } from '../../lib/auth'

type Room = {
  id: string
  name: string
  is_group: boolean
  is_public?: boolean
  member_ids: string[]
  created_by?: string
  last_message?: string
  last_message_time?: string
  description?: string
}

type Msg = {
  id: string
  sender_id: string
  sender_name?: string
  content: string
  created_at: string
}

export default function CommunicationPage() {
  const { user, loading } = useAuth()
  const router = useRouter()
  const [rooms, setRooms] = useState<Room[]>([])
  const [activeRoom, setActiveRoom] = useState<Room | null>(null)
  const [messages, setMessages] = useState<Msg[]>([])
  const [input, setInput] = useState('')
  const [listLoading, setListLoading] = useState(true)
  const [memberNames, setMemberNames] = useState<Record<string, string>>({})

  const loadRooms = useCallback(async () => {
    if (!user) return
    try {
      const { data, error } = await supabase
        .from('chat_rooms')
        .select('*')
        .order('last_message_time', { ascending: false })
      if (error) throw new Error(error.message)
      const mine = ((data as Room[]) || []).filter((r) => r.member_ids.includes(user.id))
      setRooms(mine)
      // Map member ids to names for DM titles
      const ids = Array.from(new Set(mine.flatMap((r) => r.member_ids)))
      const { data: profiles } = await supabase
        .from('profiles')
        .select('id, full_name')
        .in('id', ids)
      const map: Record<string, string> = {}
      for (const p of (profiles as { id: string; full_name?: string }[]) || []) {
        map[p.id] = p.full_name || 'Student'
      }
      setMemberNames(map)
    } catch (e) {
      console.error('rooms', e)
    } finally {
      setListLoading(false)
    }
  }, [user])

  useEffect(() => {
    loadRooms()
  }, [loadRooms])

  // Realtime room updates
  useEffect(() => {
    if (!user) return
    const channel = supabase
      .channel('web-rooms')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chat_rooms' }, () => loadRooms())
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [user, loadRooms])

  // Realtime messages for the active room
  useEffect(() => {
    if (!user || !activeRoom) return
    setMessages([])
    loadMessages()

    const channel = supabase
      .channel(`web-room-${activeRoom.id}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'chat_messages', filter: `room_id=eq.${activeRoom.id}` }, (payload) => {
        setMessages((prev) => {
          const msg = payload.new as unknown as Msg
          if (prev.some((m) => m.id === msg.id)) return prev
          return [...prev, msg]
        })
      })
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [user, activeRoom?.id])

  async function loadMessages() {
    if (!activeRoom) return
    try {
      const { data, error } = await supabase
        .from('chat_messages')
        .select('*')
        .eq('room_id', activeRoom.id)
        .order('created_at', { ascending: true })
        .limit(200)
      if (error) throw new Error(error.message)
      setMessages((data as Msg[]) || [])
    } catch (e) {
      console.error('messages', e)
    }
  }

  async function send() {
    const text = input.trim()
    if (!text || !user || !activeRoom) return
    setInput('')
    const { error } = await supabase.from('chat_messages').insert({
      room_id: activeRoom.id,
      sender_id: user.id,
      sender_name: 'You',
      content: text,
    })
    if (error) {
      console.error('send', error)
      setInput(text)
      return
    }
    await supabase.from('chat_rooms').update({
      last_message: text,
      last_message_time: new Date().toISOString(),
    }).eq('id', activeRoom.id)
  }

  async function createPublicRoom() {
    if (!user) return
    const name = prompt('Room name:')
    if (!name?.trim()) return
    const desc = prompt('Description (optional):') || ''
    const { data, error } = await supabase.from('chat_rooms').insert({
      name: name.trim(),
      is_group: true,
      is_public: true,
      member_ids: [user.id],
      created_by: user.id,
      description: desc,
    }).select()
    if (error) { alert('Failed to create room: ' + error.message); return }
    await loadRooms()
    const room = (data as Room[])?.[0]
    if (room) {
      setActiveRoom(room)
      const { error: joinErr } = await supabase.from('chat_rooms').update({
        member_ids: [user.id],
      }).eq('id', room.id)
      if (joinErr) console.error('join', joinErr)
    }
  }

  if (loading) return <Shell><div className="text-center py-20 text-gray-500">Loading…</div></Shell>

  if (!user) {
    return (
      <Shell>
        <div className="text-center py-20">
          <div className="text-5xl mb-4">💬</div>
          <h1 className="text-xl font-bold text-gray-900 mb-2">Sign in to chat</h1>
          <p className="text-sm text-gray-500 mb-6">Chat rooms and DMs are for signed-in students.</p>
          <a href="/login" className="inline-block px-6 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition">Sign In</a>
        </div>
      </Shell>
    )
  }

  // ── Chat room view ──
  if (activeRoom) {
    const title = activeRoom.is_group
      ? activeRoom.name
      : (memberNames[activeRoom.member_ids.find((id) => id !== user.id) || ''] || 'Chat')
    return (
      <div className="min-h-screen bg-gray-50 flex flex-col">
        <header className="bg-white border-b">
          <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
            <button onClick={() => setActiveRoom(null)} className="text-gray-400 hover:text-indigo-600 text-xl">←</button>
            <div className="font-bold text-gray-900 truncate">{title}</div>
            <div className="flex-1" />
            <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
          </div>
        </header>
        <div className="max-w-3xl w-full mx-auto flex-1 flex flex-col p-4">
          <div className="flex-1 bg-white border border-gray-200 rounded-2xl p-4 overflow-y-auto space-y-2 min-h-[50vh]">
            {messages.length === 0 && <div className="text-center text-gray-400 text-sm py-12">No messages yet. Say hi!</div>}
            {messages.map((m) => {
              const mine = m.sender_id === user.id
              return (
                <div key={m.id} className={`max-w-[80%] px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap ${mine ? 'ml-auto bg-indigo-600 text-white rounded-br-sm' : 'bg-gray-100 border border-gray-200 rounded-bl-sm'}`}>
                  {!mine && <div className="text-[10px] font-semibold text-gray-500 mb-0.5">{m.sender_name || 'User'}</div>}
                  {m.content}
                </div>
              )
            })}
          </div>
          <div className="flex gap-2 mt-3">
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') send() }}
              placeholder="Type a message…"
              className="flex-1 px-4 py-3 rounded-full border border-gray-300 bg-white text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
            />
            <button onClick={send} className="px-5 py-3 bg-indigo-600 text-white rounded-full text-sm font-medium hover:bg-indigo-700 transition">Send</button>
          </div>
        </div>
      </div>
    )
  }

  // ── Rooms list ──
  return (
    <Shell>
      <div className="flex items-center justify-between mb-5">
        <h1 className="text-xl font-bold text-gray-900">Communication</h1>
        <button onClick={createPublicRoom} className="px-4 py-2 bg-indigo-600 text-white rounded-xl text-sm font-medium hover:bg-indigo-700 transition">+ New Room</button>
      </div>

      {listLoading ? (
        <div className="text-center py-16 text-gray-500">Loading…</div>
      ) : rooms.length === 0 ? (
        <div className="text-center py-16">
          <div className="text-5xl mb-4">💬</div>
          <p className="text-gray-600 font-medium">No chats yet</p>
          <p className="text-sm text-gray-500 mt-1">Create a room or start chatting from the app.</p>
        </div>
      ) : (
        <div className="space-y-2">
          {rooms.map((r) => {
            const title = r.is_group
              ? r.name
              : (memberNames[r.member_ids.find((id) => id !== user.id) || ''] || 'Chat')
            return (
              <button
                key={r.id}
                onClick={() => setActiveRoom(r)}
                className="w-full flex items-center gap-4 bg-white border border-gray-200 rounded-2xl p-4 hover:shadow-md hover:border-indigo-300 transition text-left"
              >
                <div className="w-11 h-11 rounded-full bg-indigo-600/10 flex items-center justify-center text-lg">
                  {r.is_group ? '👥' : '👤'}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-gray-900 truncate">{title}</div>
                  {r.last_message ? (
                    <div className="text-xs text-gray-500 truncate">{r.last_message}</div>
                  ) : (
                    <div className="text-xs text-gray-400">{r.is_group ? (r.description || 'Group chat') : 'Direct message'}</div>
                  )}
                </div>
                <span className="text-gray-300">›</span>
              </button>
            )
          })}
        </div>
      )}
    </Shell>
  )
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b">
        <div className="max-w-3xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Communication</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-3xl mx-auto px-4 py-6">{children}</main>
    </div>
  )
}
