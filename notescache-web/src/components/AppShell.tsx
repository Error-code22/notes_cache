'use client'

import { useEffect, useRef, useState } from 'react'
import { useRouter } from 'next/navigation'
import { useAuth, signOut, type Profile } from '../lib/auth'
import { useTheme } from '../lib/theme'
import { parseRoles } from '../lib/utils'
import { ArrowBackIcon, DarkModeIcon, LightModeIcon, UserIcon } from './icons'

type Props = {
  title: string
  children: React.ReactNode
  /** Fallback only — default behavior is history.back() */
  backHref?: string
  action?: React.ReactNode
  wide?: boolean
  showChrome?: boolean
}

export default function AppShell({ title, children, backHref = '/', action, wide = false, showChrome = true }: Props) {
  const { user, profile, loading } = useAuth()
  const { mode, toggle } = useTheme()
  const [menuOpen, setMenuOpen] = useState(false)
  const menuRef = useRef<HTMLDivElement>(null)
  const router = useRouter()

  useEffect(() => {
    if (!menuOpen) return
    const onDoc = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenuOpen(false)
    }
    document.addEventListener('mousedown', onDoc)
    return () => document.removeEventListener('mousedown', onDoc)
  }, [menuOpen])

  const roles = parseRoles(profile?.role)
  const isAdmin = roles.includes('ADMIN')

  function goBack() {
    if (typeof window !== 'undefined' && window.history.length > 1) {
      router.back()
    } else {
      router.push(backHref)
    }
  }

  return (
    <div className="min-h-screen bg-[#FAFAF7] dark:bg-[#121212]">
      <header className="sticky top-0 z-20 bg-white/95 dark:bg-[#1C1C1E]/95 backdrop-blur border-b border-black/5 dark:border-white/10">
        <div className={`${wide ? 'max-w-5xl' : 'max-w-3xl'} mx-auto px-4 h-14 flex items-center gap-3`}>
          <button onClick={goBack} className="text-gray-400 hover:text-indigo-600 flex items-center shrink-0 p-1" aria-label="Back">
            <ArrowBackIcon size={22} />
          </button>
          <div className="font-bold text-gray-900 dark:text-white truncate flex-1 min-w-0">{title}</div>
          {action}
          {showChrome && (
            <>
              <button
                onClick={toggle}
                className="w-9 h-9 rounded-full flex items-center justify-center text-indigo-600 dark:text-indigo-400 hover:bg-indigo-600/10 transition shrink-0"
                title="Toggle theme"
                aria-label="Toggle theme"
              >
                {mode === 'dark' ? <LightModeIcon size={20} /> : <DarkModeIcon size={20} />}
              </button>
              <div className="relative shrink-0" ref={menuRef}>
                <button
                  onClick={() => setMenuOpen((o) => !o)}
                  className="w-9 h-9 rounded-full bg-indigo-600/10 flex items-center justify-center overflow-hidden hover:bg-indigo-600/20 transition"
                  title="Account"
                >
                  {profile?.avatar_url ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={profile.avatar_url} alt="" className="w-full h-full object-cover" />
                  ) : (
                    <UserIcon size={18} className="text-indigo-600 dark:text-indigo-400" />
                  )}
                </button>
                {menuOpen && (
                  <div className="absolute right-0 mt-2 w-48 bg-white dark:bg-[#2C2C2E] rounded-2xl shadow-lg border border-black/5 dark:border-white/10 py-1.5 z-30">
                    {!user && !loading && <Item href="/login" label="Sign In" onClick={() => setMenuOpen(false)} />}
                    <Item href="/profile" label="My Profile" onClick={() => setMenuOpen(false)} />
                    <Item href="/settings" label="Settings" onClick={() => setMenuOpen(false)} />
                    <Item href="/updates" label="Updates" onClick={() => setMenuOpen(false)} />
                    <Item href="/feedback" label="Report a Bug" onClick={() => setMenuOpen(false)} />
                    <Item href="/pricing" label="Plans" onClick={() => setMenuOpen(false)} />
                    <Item href="/downloads" label="Download App" onClick={() => setMenuOpen(false)} />
                    {isAdmin && <Item href="/admin" label="Admin" onClick={() => setMenuOpen(false)} />}
                    {user && (
                      <>
                        <div className="my-1 h-px bg-black/5 dark:bg-white/10" />
                        <button
                          onClick={async () => { setMenuOpen(false); await signOut() }}
                          className="w-full text-left px-4 py-2.5 text-sm font-semibold text-red-600 hover:bg-red-50 dark:hover:bg-red-500/10"
                        >
                          Sign Out
                        </button>
                      </>
                    )}
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      </header>
      <main className={`${wide ? 'max-w-5xl' : 'max-w-3xl'} mx-auto px-4 py-5`}>{children}</main>
    </div>
  )
}

function Item({ href, label, onClick }: { href: string; label: string; onClick: () => void }) {
  return (
    <a href={href} onClick={onClick} className="block px-4 py-2.5 text-sm text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-white/5">
      {label}
    </a>
  )
}

export function ProfileHeader({ profile }: { profile: Profile | null }) {
  const roles = parseRoles(profile?.role)
  const isAdmin = roles.includes('ADMIN')
  return (
    <div>
      <div className="font-bold text-gray-900 dark:text-white text-xl">{profile?.full_name || 'Student'}</div>
      <div className="flex items-center gap-2">
        <span className="text-[12px] text-gray-500 dark:text-gray-400">{roles.length ? roles.join(' • ') : 'STUDENT'}</span>
        {isAdmin && (
          <a href="/admin" className="px-1.5 py-0.5 rounded bg-emerald-600 text-white text-[8px] font-bold">ADMIN</a>
        )}
      </div>
    </div>
  )
}
