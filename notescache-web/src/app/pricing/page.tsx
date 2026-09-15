'use client'

import { useState } from 'react'
import AppShell from '../../components/AppShell'

const PLANS = [
  {
    title: 'Free',
    price: 'KSh 0',
    period: 'forever',
    color: '#6B7280',
    popular: false,
    features: [
      '5 AI questions per day',
      'Browse all shared notes',
      'Basic chat rooms',
      'Friend code system',
      '100MB file uploads',
    ],
    cta: 'Current Plan',
  },
  {
    title: 'Student Pro',
    price: 'KSh 250',
    period: '/month',
    color: '#1565C0',
    popular: true,
    features: [
      '50 AI questions per day',
      'AI lecture search (RAG)',
      'Web search answers',
      'Unlimited chat rooms',
      '1GB file uploads',
      'Priority support',
      'Custom avatar',
      'Read receipts',
    ],
    cta: 'Subscribe',
  },
  {
    title: 'Campus License',
    price: 'KSh 15,000',
    period: '/semester',
    color: '#2E7D32',
    popular: false,
    features: [
      'Unlimited AI for all students',
      'Bulk student enrollment',
      'Custom branding',
      'Lecturer dashboard',
      'Exam prep mode',
      'Analytics & usage reports',
      '50GB shared storage',
      'Dedicated support',
      'API access',
    ],
    cta: 'Contact Us',
  },
]

const FAQ = [
  { q: 'Can I cancel anytime?', a: 'Yes. Student Pro is month-to-month with no lock-in.' },
  { q: 'Is the free plan really free?', a: 'Yes. Browse notes, chat, and use Notesy within the daily free limits.' },
  { q: 'How do campus licenses work?', a: 'Contact us — we set up a shared license for your class or department.' },
]

export default function PricingPage() {
  const [open, setOpen] = useState<number | null>(0)

  return (
    <AppShell title="Plans & Pricing">
      <div className="text-center mb-8">
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white mb-2">Choose Your Plan</h1>
        <p className="text-sm text-gray-500">Unlock the full power of NotesCache for your studies</p>
      </div>

      <div className="space-y-4 mb-8">
        {PLANS.map((p) => (
          <div key={p.title} className="relative bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-3xl p-6">
            {p.popular && (
              <span className="absolute -top-2 right-5 px-2 py-0.5 rounded-full text-[10px] font-black text-white" style={{ backgroundColor: p.color }}>
                POPULAR
              </span>
            )}
            <div className="flex items-center gap-2 mb-1">
              <div className="font-bold text-lg text-gray-900 dark:text-white">{p.title}</div>
            </div>
            <div className="mb-4">
              <span className="text-2xl font-black" style={{ color: p.color }}>{p.price}</span>
              <span className="text-sm text-gray-500 ml-1">{p.period}</span>
            </div>
            <ul className="space-y-1.5 mb-5">
              {p.features.map((f) => (
                <li key={f} className="text-sm text-gray-700 dark:text-gray-300 flex gap-2">
                  <span style={{ color: p.color }}>✓</span> {f}
                </li>
              ))}
            </ul>
            <button
              onClick={() => {
                if (p.title === 'Student Pro') window.alert('Coming soon — payments will be enabled in a future release.')
                else if (p.title === 'Campus License') window.location.href = 'https://wa.me/254703300084?text=Campus%20License%20inquiry'
              }}
              className="w-full py-3 rounded-xl text-sm font-bold text-white"
              style={{ backgroundColor: p.cta === 'Current Plan' ? '#9CA3AF' : p.color }}
            >
              {p.cta}
            </button>
          </div>
        ))}
      </div>

      <div className="text-[11px] font-bold text-gray-400 uppercase mb-2">FAQ</div>
      <div className="space-y-2 mb-8">
        {FAQ.map((item, i) => (
          <div key={item.q} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl overflow-hidden">
            <button onClick={() => setOpen(open === i ? null : i)} className="w-full text-left px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white">
              {item.q}
            </button>
            {open === i && <p className="px-4 pb-3 text-sm text-gray-500 dark:text-gray-400">{item.a}</p>}
          </div>
        ))}
      </div>
    </AppShell>
  )
}
