'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { signInWithEmail, signUpWithEmail, signInWithGoogle, supabase } from '../../lib/auth'

export default function LoginPage() {
  const router = useRouter()
  const [mode, setMode] = useState<'signin' | 'signup' | 'forgot'>('signin')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [name, setName] = useState('')
  const [year, setYear] = useState(1)
  const [showPw, setShowPw] = useState(false)
  const [accepted, setAccepted] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [info, setInfo] = useState('')
  const [showPolicy, setShowPolicy] = useState<'terms' | 'privacy' | null>(null)

  useEffect(() => {
    let done = false
    const check = () => {
      supabase.auth.getSession().then(({ data }) => { if (!done && data.session) router.push('/') })
    }
    check()
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => { if (!done && session) router.push('/') })
    return () => { done = true; sub.subscription.unsubscribe() }
  }, [router])

  async function submit() {
    setError(''); setInfo('')
    if (mode === 'forgot') {
      if (!email) { setError('Email is required.'); return }
      setBusy(true)
      const { error: err } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/login`,
      })
      setBusy(false)
      if (err) setError(err.message)
      else setInfo('Check your email for a reset link!')
      return
    }
    if (!email || !password) { setError('Email and password are required.'); return }
    if (mode === 'signup') {
      if (password !== confirm) { setError('Passwords do not match.'); return }
      if (!name.trim()) { setError('Full name is required.'); return }
      if (password.length < 6) { setError('Password must be at least 6 characters.'); return }
      if (!accepted) { setError('Please accept the terms & privacy policy.'); return }
    }
    setBusy(true)
    try {
      if (mode === 'signin') await signInWithEmail(email, password)
      else await signUpWithEmail(email, password, name.trim(), year)
      router.push('/')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Something went wrong.')
    } finally { setBusy(false) }
  }

  async function google() {
    setError('')
    setBusy(true)
    try { await signInWithGoogle() } catch (e) {
      setError(e instanceof Error ? e.message : 'Google sign-in failed.')
      setBusy(false)
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-600 via-indigo-500 to-violet-600 flex items-center justify-center px-4 py-8">
      <div className="w-full max-w-md bg-white dark:bg-[#1C1C1E] rounded-3xl shadow-2xl p-8">
        <div className="text-center mb-6">
          <div className="w-16 h-16 mx-auto mb-3 rounded-2xl bg-indigo-600/10 flex items-center justify-center text-2xl font-bold text-indigo-600">N</div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">NotesCache</h1>
          <p className="text-sm text-gray-500 mt-1">
            {mode === 'signin' ? 'Welcome back!' : mode === 'signup' ? 'Create your account' : 'Reset your password'}
          </p>
        </div>

        {mode !== 'forgot' && (
          <>
            <button onClick={google} disabled={busy} className="w-full flex items-center justify-center gap-2 px-4 py-3 border border-gray-300 dark:border-white/15 rounded-xl text-sm font-medium text-gray-700 dark:text-gray-200 hover:bg-gray-50 dark:hover:bg-white/5 transition disabled:opacity-50">
              <span className="text-lg font-bold text-indigo-600">G</span> Continue with Google
            </button>
            <div className="flex items-center gap-3 my-5">
              <div className="flex-1 h-px bg-gray-200 dark:bg-white/10" />
              <span className="text-xs text-gray-400 font-medium">OR</span>
              <div className="flex-1 h-px bg-gray-200 dark:bg-white/10" />
            </div>
          </>
        )}

        <div className="space-y-3">
          {mode === 'signup' && (
            <>
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Full Name" className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
              <div className="flex gap-2">
                {[1, 2, 3, 4].map((y) => (
                  <button key={y} onClick={() => setYear(y)} className={`flex-1 py-2 rounded-xl text-sm font-medium border transition ${year === y ? 'bg-indigo-600 text-white border-indigo-600' : 'bg-transparent text-gray-600 dark:text-gray-300 border-gray-300 dark:border-white/15'}`}>Yr {y}</button>
                ))}
              </div>
            </>
          )}
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder="Email Address" className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
          {mode !== 'forgot' && (
            <div className="relative">
              <input value={password} onChange={(e) => setPassword(e.target.value)} type={showPw ? 'text' : 'password'} placeholder="Password" className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
              <button type="button" onClick={() => setShowPw((v) => !v)} className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-gray-400">
                {showPw ? 'Hide' : 'Show'}
              </button>
            </div>
          )}
          {mode === 'signup' && (
            <>
              <input value={confirm} onChange={(e) => setConfirm(e.target.value)} type="password" placeholder="Confirm Password" className="w-full px-4 py-3 rounded-xl border border-gray-300 dark:border-white/15 bg-transparent text-sm text-gray-900 dark:text-white" />
              <label className="flex items-start gap-2 text-xs text-gray-500">
                <input type="checkbox" checked={accepted} onChange={(e) => setAccepted(e.target.checked)} className="mt-0.5" />
                <span>
                  I agree to the{' '}
                  <button type="button" className="text-indigo-600 underline" onClick={() => setShowPolicy('terms')}>Terms</button>
                  {' '}and{' '}
                  <button type="button" className="text-indigo-600 underline" onClick={() => setShowPolicy('privacy')}>Privacy Policy</button>
                </span>
              </label>
            </>
          )}
        </div>

        {error && <p className="text-sm text-red-600 mt-3">{error}</p>}
        {info && <p className="text-sm text-emerald-600 mt-3">{info}</p>}

        <button onClick={submit} disabled={busy} className="w-full mt-4 py-3 bg-indigo-600 text-white rounded-xl text-sm font-bold hover:bg-indigo-700 transition disabled:opacity-50">
          {busy ? 'Please wait…' : mode === 'signin' ? 'Sign In' : mode === 'signup' ? 'Sign Up' : 'Send Reset Email'}
        </button>

        <div className="text-center mt-4 space-y-2">
          {mode !== 'forgot' && (
            <button onClick={() => { setMode(mode === 'signin' ? 'signup' : 'signin'); setError(''); setInfo('') }} className="text-sm text-indigo-600 font-medium hover:underline block w-full">
              {mode === 'signin' ? 'New here? Create an account' : 'Already have an account? Sign in'}
            </button>
          )}
          {mode === 'signin' && (
            <button onClick={() => { setMode('forgot'); setError(''); setInfo('') }} className="text-sm text-gray-500 hover:text-indigo-600">
              Forgot Password?
            </button>
          )}
          {mode === 'forgot' && (
            <button onClick={() => { setMode('signin'); setError(''); setInfo('') }} className="text-sm text-indigo-600 font-medium">
              Back to Sign In
            </button>
          )}
          {mode !== 'forgot' && (
            <a href="/" className="text-sm text-gray-400 hover:text-gray-600 block">Continue as Guest (Demo)</a>
          )}
        </div>
      </div>

      {showPolicy && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setShowPolicy(null)}>
          <div className="bg-white dark:bg-[#1C1C1E] rounded-2xl max-w-lg w-full max-h-[80vh] overflow-y-auto p-6" onClick={(e) => e.stopPropagation()}>
            <h3 className="font-bold text-lg text-gray-900 dark:text-white mb-3">
              {showPolicy === 'terms' ? 'Terms & Conditions' : 'Privacy Policy'}
            </h3>
            <p className="text-sm text-gray-600 dark:text-gray-300 leading-relaxed">
              {showPolicy === 'terms'
                ? 'By using NotesCache you agree to use the platform for lawful educational purposes only. Do not upload copyrighted material you do not have rights to share. The service is provided as-is for student collaboration and study support.'
                : 'We store your account email, profile, notes you upload, and AI chat history needed to run the service. Guest usage is limited and local. We do not sell your data. Contact support to request account deletion.'}
            </p>
            <button onClick={() => setShowPolicy(null)} className="mt-4 w-full py-2.5 bg-indigo-600 text-white rounded-xl text-sm font-bold">Close</button>
          </div>
        </div>
      )}
    </div>
  )
}
