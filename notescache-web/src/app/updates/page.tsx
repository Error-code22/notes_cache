'use client'

import { useEffect, useState } from 'react'
import { supabase } from '../../lib/auth'
import AppShell from '../../components/AppShell'
import { MegaphoneIcon } from '../../components/icons'

type Update = { id: string; title?: string; content?: string; created_at?: string }

export default function UpdatesPage() {
  const [items, setItems] = useState<Update[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    const load = async () => {
      const { data } = await supabase.from('app_updates').select('*').order('created_at', { ascending: false }).limit(50)
      if (!cancelled) {
        setItems((data as Update[]) || [])
        setLoading(false)
      }
    }
    load()
    const channel = supabase
      .channel('app_updates_live')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'app_updates' }, () => load())
      .subscribe()
    return () => { cancelled = true; supabase.removeChannel(channel) }
  }, [])

  return (
    <AppShell title="App Updates">
      {loading ? (
        <div className="text-center py-16 text-gray-400">Loading…</div>
      ) : items.length === 0 ? (
        <div className="text-center py-16">
          <div className="flex justify-center mb-3 text-indigo-300"><MegaphoneIcon size={48} /></div>
          <p className="font-bold text-gray-900 dark:text-white">No updates yet!</p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((u) => (
            <div key={u.id} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-5">
              <div className="flex items-center gap-2 mb-2">
                <MegaphoneIcon size={18} className="text-indigo-600" />
                <div className="font-bold text-gray-900 dark:text-white">{u.title || 'Update'}</div>
              </div>
              <p className="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">{u.content}</p>
              {u.created_at && (
                <div className="text-[10px] text-gray-400 mt-2">{new Date(u.created_at).toLocaleString()}</div>
              )}
            </div>
          ))}
        </div>
      )}
    </AppShell>
  )
}
