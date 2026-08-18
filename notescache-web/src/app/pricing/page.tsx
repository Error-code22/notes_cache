'use client'

import { useEffect, useState } from 'react'
import { supabase } from '../../lib/auth'

type Plan = {
  id: string
  name: string
  price: string
  period: string
  description?: string
  features: string[]
  color?: string
  popular?: boolean
}

export default function PricingPage() {
  const [plans, setPlans] = useState<Plan[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    (async () => {
      try {
        const { data } = await supabase
          .from('pricing_plans')
          .select('*')
          .eq('active', true)
          .order('sort_order')
        setPlans((data as Plan[]) || [])
      } catch { /* ignore */ }
      setLoading(false)
    })()
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b">
        <div className="max-w-4xl mx-auto px-4 h-14 flex items-center gap-4">
          <a href="/" className="text-gray-400 hover:text-indigo-600 text-xl">←</a>
          <div className="font-bold text-gray-900">Plans</div>
          <div className="flex-1" />
          <a href="/downloads" className="text-sm text-gray-500 hover:text-indigo-600 transition">Download App</a>
        </div>
      </header>
      <main className="max-w-4xl mx-auto px-4 py-8">
        <h1 className="text-2xl font-bold text-gray-900 text-center mb-2">Choose Your Plan</h1>
        <p className="text-sm text-gray-500 text-center mb-8">Unlock the full power of NotesCache for your studies</p>

        {loading ? (
          <div className="text-center py-16 text-gray-500">Loading…</div>
        ) : (
          <div className="grid sm:grid-cols-3 gap-4">
            {plans.map((p) => {
              const color = p.color || '#607D8B'
              return (
                <div
                  key={p.id}
                  className={`bg-white rounded-2xl p-6 ${p.popular ? 'border-2 shadow-lg' : 'border border-gray-200'}`}
                  style={p.popular ? { borderColor: color } : undefined}
                >
                  {p.popular && (
                    <span className="inline-block px-3 py-1 rounded-full text-[10px] font-bold text-white mb-3" style={{ backgroundColor: color }}>
                      MOST POPULAR
                    </span>
                  )}
                  <h2 className="font-bold text-lg text-gray-900">{p.name}</h2>
                  {p.description && <p className="text-xs text-gray-500 mt-1 mb-3">{p.description}</p>}
                  <div className="mb-4">
                    <span className="text-3xl font-bold" style={{ color }}>{p.price}</span>
                    <span className="text-gray-400 text-sm ml-1">{p.period}</span>
                  </div>
                  <ul className="space-y-2 mb-6">
                    {(p.features || []).map((f, i) => (
                      <li key={i} className="flex items-start gap-2 text-sm text-gray-700">
                        <span style={{ color }}>✓</span>
                        <span>{f}</span>
                      </li>
                    ))}
                  </ul>
                  <button
                    className="w-full py-2.5 rounded-xl text-sm font-bold text-white transition hover:opacity-90"
                    style={{ backgroundColor: color }}
                  >
                    {p.popular ? 'Coming Soon' : 'Free'}
                  </button>
                </div>
              )
            })}
          </div>
        )}
        <p className="text-xs text-gray-400 text-center mt-8">
          All prices in Kenya Shillings (KSh). Payments are not live yet — the app is free while we finish setup.
        </p>
      </main>
    </div>
  )
}
