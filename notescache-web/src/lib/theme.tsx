'use client'

import { createContext, useContext, useEffect, useState } from 'react'

type Mode = 'light' | 'dark'

type ThemeValue = { mode: Mode; toggle: () => void }

const ThemeContext = createContext<ThemeValue>({ mode: 'light', toggle: () => {} })

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [mode, setMode] = useState<Mode>('light')
  const [ready, setReady] = useState(false)

  useEffect(() => {
    const saved = localStorage.getItem('nc_theme') as Mode | null
    if (saved === 'light' || saved === 'dark') {
      setMode(saved)
    } else if (window.matchMedia('(prefers-color-scheme: dark)').matches) {
      setMode('dark')
    }
    setReady(true)
  }, [])

  useEffect(() => {
    if (!ready) return
    document.documentElement.classList.toggle('dark', mode === 'dark')
    localStorage.setItem('nc_theme', mode)
  }, [mode, ready])

  return (
    <ThemeContext.Provider
      value={{ mode, toggle: () => setMode((m) => (m === 'light' ? 'dark' : 'light')) }}
    >
      {children}
    </ThemeContext.Provider>
  )
}

export function useTheme() {
  return useContext(ThemeContext)
}
