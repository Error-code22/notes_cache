import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'NotesCache — Download the App',
  description: 'Your campus study companion. Download the NotesCache Android app.',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
