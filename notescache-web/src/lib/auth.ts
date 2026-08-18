'use client'

import { createClient, type User } from '@supabase/supabase-js'
import { useEffect, useState } from 'react'

export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
)

export type Profile = {
  id: string
  full_name?: string | null
  email?: string | null
  year_level?: number | null
  role?: string | null
  avatar_url?: string | null
  bio?: string | null
  is_profile_public?: boolean
}

export function useAuth() {
  const [user, setUser] = useState<User | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setUser(data.session?.user ?? null)
      setLoading(false)
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
      if (!session?.user) {
        setProfile(null)
        setLoading(false)
      }
    })

    return () => sub.subscription.unsubscribe()
  }, [])

  // Fetch profile whenever the user changes
  useEffect(() => {
    if (!user) {
      setProfile(null)
      return
    }
    (async () => {
      try {
        const { data } = await supabase
          .from('profiles')
          .select('id, full_name, year_level, role, avatar_url, bio, is_profile_public')
          .eq('id', user.id)
          .maybeSingle()
        setProfile((data as Profile) || null)
      } catch {
        setProfile(null)
      }
    })()
  }, [user])

  const isGuest = !user

  return { user, profile, loading, isGuest }
}

export async function signInWithEmail(email: string, password: string) {
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw new Error(error.message)
}

export async function signUpWithEmail(email: string, password: string, fullName: string, yearLevel: number) {
  const { error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName, year_level: yearLevel, role: 'student' } },
  })
  if (error) throw new Error(error.message)
}

export async function signInWithGoogle() {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin },
  })
  if (error) throw new Error(error.message)
}

export async function signOut() {
  await supabase.auth.signOut()
}
