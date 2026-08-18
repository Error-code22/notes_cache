'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { signInWithEmail, signUpWithEmail, signInWithGoogle, supabase } from '../../lib/auth'

export default function LoginPage() {
  const router = useRouter()
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [name, setName] = useState('')
  const [year, setYear] = useState(1)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let done = false
    const check = () => {
      supabase.auth.getSession().then(({ data }) => {
        if (!done && data.session) router.push('/')
      })
    }
    check()
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!done && session) router.push('/')
    })
    return () => {
      done = true
      sub.subscription.unsubscribe()
    }
  }, [router])

  async function submit() {
    setError('')
    if (!email || !password) { setError('Email and password are required.'); return }
    if (mode === 'signup') {
      if (password !== confirm) { setError('Passwords do not match.'); return }
      if (!name.trim()) { setError('Full name is required.'); return }
      if (password.length < 6) { setError('Password must be at least 6 characters.'); return }
    }
    setBusy(true)
    try {
      if (mode === 'signin') {
        await signInWithEmail(email, password)
      } else {
        await signUpWithEmail(email, password, name.trim(), year)
      }
      router.push('/')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong.')
    } finally {
      setBusy(false)
    }
  }

  async function google() {
    setError('')
    setBusy(true)
    try {
      await signInWithGoogle()
      // OAuth redirects away; on return the session exists
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Google sign-in failed.')
      setBusy(false)
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-600 via-indigo-500 to-violet-600 flex items-center justify-center px-4">
      <div className="w-full max-w-md bg-white rounded-3xl shadow-2xl p-8">
        <div className="text-center mb-6">
          <div className="w-16 h-16 mx-auto mb-3 rounded-2xl bg-indigo-600/10 flex items-center justify-center text-3xl">📚</div>
          <h1 className="text-2xl font-bold text-gray-900">NotesCache</h1>
          <p className="text-sm text-gray-500 mt-1">{mode === 'signin' ? 'Welcome back!' : 'Create your account'}</p>
        </div>

        <button
          onClick={google}
          disabled={busy}
          className="w-full flex items-center justify-center gap-2 px-4 py-3 border border-gray-300 rounded-xl text-sm font-medium text-gray-700 hover:bg-gray-50 transition disabled:opacity-50"
        >
          <span className="text-lg">G</span> Continue with Google
        </button>

        <div className="flex items-center gap-3 my-5">
          <div className="flex-1 h-px bg-gray-200" />
          <span className="text-xs text-gray-400 font-medium">OR</span>
          <div className="flex-1 h-px bg-gray-200" />
        </div>

        <div className="space-y-3">
          {mode === 'signup' && (
            <>
              <input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Full Name"
                className="w-full px-4 py-3 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
              />
              <div className="flex gap-2">
                {[1, 2, 3, 4].map((y) => (
                  <button
                    key={y}
                    onClick={() => setYear(y)}
                    className={`flex-1 py-2 rounded-xl text-sm font-medium border transition ${year === y ? 'bg-indigo-600 text-white border-indigo-600' : 'bg-white text-gray-600 border-gray-300 hover:border-indigo-400'}`}
                  >
                    Yr {y}
                  </button>
                ))}
              </div>
            </>
          )}
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            type="email"
            placeholder="Email Address"
            className="w-full px-4 py-3 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
          <input
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            type="password"
            placeholder="Password"
            className="w-full px-4 py-3 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
          />
          {mode === 'signup' && (
            <input
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
              type="password"
              placeholder="Confirm Password"
              className="w-full px-4 py-3 rounded-xl border border-gray-300 text-sm focus:outline-none focus:ring-2 focus:ring-indigo-400"
            />
          )}
        </div>

        {error && <p className="text-sm text-red-600 mt-3">{error}</p>}

        <button
          onClick={submit}
          disabled={busy}
          className="w-full mt-4 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50"
        >
          {busy ? 'Please wait…' : mode === 'signin' ? 'Sign In' : 'Sign Up'}
        </button>

        <div className="text-center mt-4">
          <button
            onClick={() => { setMode(mode === 'signin' ? 'signup' : 'signin'); setError('') }}
            className="text-sm text-indigo-600 font-medium hover:underline"
          >
            {mode === 'signin' ? 'New here? Create an account' : 'Already have an account? Sign in'}
          </button>
        </div>
        <div className="text-center mt-2">
          <a href="/" className="text-sm text-gray-400 hover:text-gray-600">← Continue as guest</a>
        </div>
      </div>
    </div>
  )
}
