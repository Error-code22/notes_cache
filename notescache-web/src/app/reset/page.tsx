'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '../../lib/auth'

/**
 * Landing page for Supabase password-recovery links.
 *
 * The link is a PKCE code (`?code=...`). supabase-js exchanges it on load and
 * emits a session, which is what lets updateUser() work without the old
 * password. Hash-style links (`#access_token=...&type=recovery`) are handled
 * by the same client, so both email templates work.
 */
export default function ResetPage() {
  const router = useRouter()
  const [ready, setReady] = useState(false)
  const [hasSession, setHasSession] = useState(false)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [done, setDone] = useState(false)

  useEffect(() => {
    let cancelled = false

    const query = new URLSearchParams(window.location.search)
    const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''))
    const linkError = query.get('error_description') || hash.get('error_description')
    if (linkError) {
      setError(linkError.replace(/\+/g, ' '))
      setReady(true)
      return
    }

    // Give supabase-js a moment to exchange the PKCE code before declaring
    // the link dead.
    const fallback = setTimeout(() => { if (!cancelled) setReady(true) }, 4000)

    supabase.auth.getSession().then(({ data }) => {
      if (cancelled) return
      if (data.session) {
        setEmail(data.session.user.email ?? '')
        setHasSession(true)
        setReady(true)
        clearTimeout(fallback)
      }
    })

    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (cancelled) return
      if (session) {
        setEmail(session.user.email ?? '')
        setHasSession(true)
        setReady(true)
        clearTimeout(fallback)
      }
    })

    return () => {
      cancelled = true
      clearTimeout(fallback)
      sub.subscription.unsubscribe()
    }
  }, [])

  async function submit() {
    setError('')
    if (!hasSession) { setError('This reset link is invalid or has expired. Request a new one.'); return }
    if (password.length < 8) { setError('Use at least 8 characters.'); return }
    if (password !== confirm) { setError('Passwords do not match.'); return }

    setBusy(true)
    const { error: err } = await supabase.auth.updateUser({ password })
    setBusy(false)
    if (err) { setError(err.message); return }

    // Force a fresh sign-in with the new password.
    await supabase.auth.signOut()
    setDone(true)
    setTimeout(() => router.replace('/login?reset=1'), 1200)
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-600 via-indigo-500 to-violet-600 flex items-center justify-center px-4 py-8">
      <div className="w-full max-w-md bg-white dark:bg-[#1C1C1E] rounded-3xl shadow-2xl p-8">
        <div className="text-center mb-6">
          <div className="w-16 h-16 mx-auto mb-3 rounded-2xl bg-indigo-600/10 flex items-center justify-center text-2xl font-bold text-indigo-600">N</div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Set a new password</h1>
          <p className="text-sm text-gray-500 mt-1">
            {email ? `For ${email}` : 'Finish resetting your NotesCache password'}
          </p>
        </div>

        {!ready && (
          <p className="text-sm text-gray-500 text-center py-8">Checking your reset link…</p>
        )}

        {ready && !hasSession && (
          <div className="text-center space-y-4">
            <p className="text-sm text-red-600">
              {error || 'This reset link is invalid or has expired.'}
            </p>
            <button
              onClick={() => router.replace('/login')}
              className="w-full py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition"
            >
              Request a new link
            </button>
          </div>
        )}

        {ready && hasSession && !done && (
          <>
            <div className="space-y-3">
              <input
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                type="password"
                placeholder="New password (min. 8 characters)"
                autoComplete="new-password"
                className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
              />
              <input
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                type="password"
                placeholder="Confirm new password"
                autoComplete="new-password"
                className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white"
              />
            </div>

            {error && <p className="text-sm text-red-600 mt-3">{error}</p>}

            <button
              onClick={submit}
              disabled={busy}
              className="w-full mt-4 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50"
            >
              {busy ? 'Saving…' : 'Update password'}
            </button>
            <button
              onClick={() => router.replace('/login')}
              className="w-full mt-3 text-sm text-gray-500 hover:text-indigo-600"
            >
              Back to sign in
            </button>
          </>
        )}

        {done && (
          <div className="text-center space-y-3 py-4">
            <p className="text-sm text-emerald-600 font-medium">Password updated.</p>
            <p className="text-sm text-gray-500">Taking you to sign in…</p>
          </div>
        )}
      </div>
    </div>
  )
}
