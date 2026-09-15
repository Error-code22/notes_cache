'use client'

import { useEffect, useRef, useState } from 'react'
import { useAuth, signOut, type Profile } from '../lib/auth'
import { useTheme } from '../lib/theme'
import {
  BookIcon, VolunteerIcon, ChatIcon, BrainIcon, ConstructionIcon,
  UserIcon, DarkModeIcon, LightModeIcon,
} from '../components/icons'

type HubCard = {
  title: string
  subtitle: string
  icon: React.ReactNode
  color: string
  href: string
}

function parseRoles(profile: Profile | null): string[] {
  return String(profile?.role || '')
    .split(',')
    .map((r) => r.trim())
    .filter(Boolean)
    .map((r) => r.toUpperCase())
}

export default function Home() {
  const { user, profile, loading } = useAuth()
  const { mode, toggle } = useTheme()
  const [showComms, setShowComms] = useState(true)
  const [roadmapCount, setRoadmapCount] = useState(0)
  const [configLoading, setConfigLoading] = useState(true)
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const [{ data: config }, { data: roadmap }] = await Promise.all([
          fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/app_config?select=key,value`, {
            headers: {
              apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
              Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!}`,
            },
          }).then((r) => r.json()).catch(() => []),
          fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/roadmap_items?select=id&active=eq.true`, {
            headers: {
              apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
              Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!}`,
            },
          }).then((r) => r.json()).catch(() => []),
        ])
        if (cancelled) return
        const rows = Array.isArray(config) ? config : []
        const row = rows.find((r: { key: string }) => r.key === 'show_comms_button')
        if (row && row.value === 'false') setShowComms(false)
        setRoadmapCount(Array.isArray(roadmap) ? roadmap.length : 0)
      } catch { /* ignore */ }
      if (!cancelled) setConfigLoading(false)
    })()
    return () => { cancelled = true }
  }, [])

  useEffect(() => {
    if (!menuOpen) return
    const onDoc = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false)
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [menuOpen])

  const roles = parseRoles(profile)
  const isAdmin = roles.includes('ADMIN')
  const displayName = profile?.full_name || (user ? 'Student' : 'Guest')
  const roleLine = user
    ? (roles.length ? roles.join(' • ') : 'STUDENT')
    : 'GUEST MODE'

  const cards: HubCard[] = [
    {
      title: 'Academic Notes',
      subtitle: 'Browse and read the shared library',
      icon: <BookIcon size={32} />,
      color: '#3B82F6',
      href: '/notes',
    },
    {
      title: 'Donate Notes',
      subtitle: 'Share notes with everyone on the app',
      icon: <VolunteerIcon size={32} />,
      color: '#EC4899',
      href: '/donate',
    },
  ]
  if (showComms) {
    cards.push({
      title: 'Communication',
      subtitle: 'Chat with friends and study groups',
      icon: <ChatIcon size={32} />,
      color: '#F97316',
      href: '/communication',
    })
  }

  return (
    <div className="min-h-screen bg-[#FAFAF7] dark:bg-[#121212]">
      {/* App bar — mirrors Flutter dashboard */}
      <header className="sticky top-0 z-20 bg-white/95 dark:bg-[#1C1C1E]/95 backdrop-blur border-b border-black/5 dark:border-white/10">
        <div className="max-w-3xl mx-auto px-5 min-h-16 py-3 flex items-center gap-3">
          <div className="flex-1 min-w-0">
            <div className="font-bold text-gray-900 dark:text-white text-xl leading-tight truncate">
              {loading ? '…' : displayName}
            </div>
            <div className="flex items-center gap-2 mt-0.5">
              <span className="text-[12px] text-gray-500 dark:text-gray-400 truncate">
                {roleLine}
              </span>
              {isAdmin && (
                <a
                  href="/admin"
                  className="shrink-0 px-1.5 py-0.5 rounded bg-emerald-600 text-white text-[8px] font-bold tracking-wide hover:bg-emerald-700 transition"
                >
                  ADMIN
                </a>
              )}
            </div>
          </div>

          <button
            onClick={toggle}
            className="w-10 h-10 rounded-full flex items-center justify-center text-indigo-600 dark:text-indigo-400 hover:bg-indigo-600/10 transition"
            title={mode === 'dark' ? 'Light mode' : 'Dark mode'}
            aria-label="Toggle theme"
          >
            {mode === 'dark' ? <LightModeIcon size={22} /> : <DarkModeIcon size={22} />}
          </button>

          <div className="relative" ref={menuRef}>
            <button
              onClick={() => setMenuOpen((o) => !o)}
              className="w-10 h-10 rounded-full bg-indigo-600/10 dark:bg-indigo-400/15 flex items-center justify-center overflow-hidden hover:bg-indigo-600/20 transition"
              title="Account"
              aria-label="Account menu"
            >
              {profile?.avatar_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={profile.avatar_url} alt="" className="w-full h-full object-cover" />
              ) : (
                <UserIcon size={20} className="text-indigo-600 dark:text-indigo-400" />
              )}
            </button>

            {menuOpen && (
              <div className="absolute right-0 mt-2 w-52 bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-lg border border-black/5 dark:border-white/10 py-1.5 z-30">
                {!user && (
                  <>
                    <MenuItem href="/login" label="Sign In" onClick={() => setMenuOpen(false)} />
                    <div className="my-1 h-px bg-black/5 dark:bg-white/10" />
                  </>
                )}
                <MenuItem href="/profile" label="My Profile" onClick={() => setMenuOpen(false)} />
                <MenuItem href="/updates" label="Updates" onClick={() => setMenuOpen(false)} />
                <MenuItem href="/feedback" label="Report a Bug" onClick={() => setMenuOpen(false)} />
                <MenuItem href="/downloads" label="Download App" onClick={() => setMenuOpen(false)} />
                {user && (
                  <>
                    <div className="my-1 h-px bg-black/5 dark:bg-white/10" />
                    <button
                      onClick={async () => { setMenuOpen(false); await signOut() }}
                      className="w-full text-left px-4 py-2.5 text-sm font-semibold text-red-600 hover:bg-red-50 dark:hover:bg-red-500/10 transition"
                    >
                      Sign Out
                    </button>
                  </>
                )}
              </div>
            )}
          </div>
        </div>
      </header>

      {/* Demo banner — guests only */}
      {!loading && !user && (
        <div className="bg-amber-500 text-white">
          <div className="max-w-3xl mx-auto px-5 py-2.5 flex items-center justify-between gap-3">
            <span className="text-[13px] font-medium">
              Demo mode: browsing &amp; donating only. Sign in for full access.
            </span>
            <a href="/login" className="text-[12px] font-bold underline shrink-0">SIGN IN</a>
          </div>
        </div>
      )}

      <main className="max-w-3xl mx-auto px-5 py-5">
        {configLoading || loading ? (
          <div className="text-center py-20 text-gray-400 dark:text-gray-500">Loading…</div>
        ) : (
          <div className="space-y-4">
            {cards.map((card) => (
              <a
                key={card.title}
                href={card.href}
                className="flex items-center gap-5 bg-white dark:bg-[#1C1C1E] rounded-3xl border border-black/5 dark:border-white/10 p-6 hover:shadow-md transition"
                style={{ borderColor: undefined }}
                onMouseEnter={(e) => { e.currentTarget.style.borderColor = `${card.color}66` }}
                onMouseLeave={(e) => { e.currentTarget.style.borderColor = '' }}
              >
                <div
                  className="p-4 rounded-2xl flex items-center justify-center shrink-0"
                  style={{ backgroundColor: `${card.color}1A`, color: card.color }}
                >
                  {card.icon}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-bold text-gray-900 dark:text-white text-lg">{card.title}</div>
                  <div className="text-[13px] text-gray-500 dark:text-gray-400">{card.subtitle}</div>
                </div>
                <span className="text-gray-300 dark:text-gray-600 text-xl shrink-0">›</span>
              </a>
            ))}

            {/* Notesy Memory Lab — accent card with NEW badge */}
            <a
              href="/chat"
              className="block bg-white dark:bg-[#1C1C1E] rounded-3xl border border-violet-500/20 p-[22px] hover:shadow-md transition"
            >
              <div className="flex items-center gap-[18px]">
                <div className="w-16 h-16 rounded-2xl bg-violet-600/12 flex items-center justify-center shrink-0 text-violet-600 dark:text-violet-400">
                  <BrainIcon size={34} />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <div className="flex-1 font-bold text-gray-900 dark:text-white text-lg truncate">
                      Notesy Memory Lab
                    </div>
                    <span className="shrink-0 px-2 py-1 rounded-md bg-amber-500/15 text-amber-600 dark:text-amber-400 text-[10px] font-black">
                      NEW
                    </span>
                  </div>
                  <div className="text-[12px] text-gray-500 dark:text-gray-400 mt-1">
                    Quizzes, flashcards &amp; memory tools
                  </div>
                </div>
              </div>
            </a>

            {/* What's Coming — compact list tile */}
            <a
              href="/whats-coming"
              className="flex items-center gap-3 bg-white dark:bg-[#1C1C1E] rounded-2xl border border-black/10 dark:border-white/10 p-4 hover:shadow-md transition"
            >
              <div className="w-10 h-10 rounded-xl bg-indigo-600/10 dark:bg-indigo-400/15 flex items-center justify-center text-indigo-600 dark:text-indigo-400 shrink-0">
                <ConstructionIcon size={20} />
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-gray-900 dark:text-white text-sm">What&apos;s Coming</div>
                <div className="text-[12px] text-gray-500 dark:text-gray-400">
                  {roadmapCount === 0
                    ? 'See upcoming features'
                    : `${roadmapCount} feature${roadmapCount > 1 ? 's' : ''} in the pipeline`}
                </div>
              </div>
              <span className="text-gray-300 dark:text-gray-600 shrink-0">›</span>
            </a>
          </div>
        )}
      </main>
    </div>
  )
}

function MenuItem({ href, label, onClick }: { href: string; label: string; onClick: () => void }) {
  return (
    <a
      href={href}
      onClick={onClick}
      className="block px-4 py-2.5 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-white/5 transition"
    >
      {label}
    </a>
  )
}
