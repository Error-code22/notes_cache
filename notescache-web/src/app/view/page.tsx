'use client'

import { useEffect, useRef, useState, Suspense } from 'react'
import { useSearchParams } from 'next/navigation'

// Document viewer: renders a file by URL using the best in-browser approach
// per extension. No server involved — files are public-by-URL.

function ViewerContent() {
  const params = useSearchParams()
  const url = params.get('url') || ''
  const extParam = (params.get('ext') || '').toLowerCase()
  const [mode, setMode] = useState<'loading' | 'ready' | 'error'>('loading')
  const [error, setError] = useState('')
  const [ext, setExt] = useState('')
  const docxHostRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!url) {
      setMode('error')
      setError('No document URL provided. Use: /view?url=...')
      return
    }
    try {
      new URL(url)
    } catch {
      setMode('error')
      setError('That URL looks invalid.')
      return
    }
    // Cloudinary URLs have no extension — trust the ?ext= param the app sends.
    // Otherwise derive from the URL path, only when the last segment looks
    // like a real extension (short, after the final slash).
    let e = ''
    if (extParam.startsWith('.')) {
      e = extParam
    } else if (extParam) {
      e = '.' + extParam
    }
    if (!e) {
      const path = new URL(url).pathname
      const last = path.substring(path.lastIndexOf('/') + 1)
      const dot = last.lastIndexOf('.')
      if (dot > 0 && last.length - dot <= 5) {
        e = last.substring(dot).toLowerCase()
      }
    }
    setExt(e)
    setMode('ready')
  }, [url, extParam])

  useEffect(() => {
    if (mode !== 'ready') return
    const renderDocx = async () => {
      try {
        const mod = await import('docx-preview')
        const res = await fetch(url)
        if (!res.ok) throw new Error('Download failed (HTTP ' + res.status + ')')
        const blob = await res.blob()
        if (docxHostRef.current) {
          await mod.renderAsync(blob, docxHostRef.current, undefined, {
            inWrapper: true,
            ignoreWidth: true,
            ignoreHeight: true,
            breakPages: false,
          })
        }
      } catch (err: unknown) {
        setError(err instanceof Error ? err.message : 'Failed to render document')
      }
    }
    if (['.docx'].includes(ext)) renderDocx()
  }, [mode, ext, url])

  const isPdf = ext === '.pdf'
  const isDocx = ext === '.docx'
  const isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'].includes(ext)
  const isAudio = ['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'].includes(ext)
  const isVideo = ['.mp4', '.mov', '.mkv', '.webm', '.m4v'].includes(ext)
  const isText = ['.txt', '.md', '.csv', '.json', '.xml', '.html', '.log', '.py', '.js', '.ts', '.dart', '.sql', '.sh', '.yaml', '.yml', '.css'].includes(ext)

  return (
    <main className="min-h-screen bg-gray-50">
      <header className="bg-white border-b sticky top-0 z-10">
        <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between">
          <a href="/" className="font-bold text-indigo-600">NotesCache</a>
          <div className="flex items-center gap-3">
            <span className="text-xs text-gray-500">Viewing <b className="text-gray-700">{ext || 'file'}</b></span>
            <a
              href={url}
              download
              className="px-3 py-1.5 bg-indigo-600 text-white rounded-lg text-xs font-medium hover:bg-indigo-700 transition"
            >
              Download
            </a>
          </div>
        </div>
      </header>

      <div className="max-w-5xl mx-auto p-4">
        {mode === 'loading' && <p className="text-center text-gray-500 py-16">Loading…</p>}

        {mode === 'error' && (
          <div className="text-center py-16">
            <div className="text-4xl mb-3">⚠️</div>
            <p className="text-gray-700 font-medium">{error}</p>
            <a href="/" className="inline-block mt-4 text-indigo-600 text-sm hover:underline">← Back to home</a>
          </div>
        )}

        {mode === 'ready' && isPdf && (
          <iframe src={url} className="w-full h-[85vh] rounded-xl border border-gray-200 bg-white" title="PDF viewer" />
        )}

        {mode === 'ready' && isDocx && (
          <div className="bg-white rounded-xl border border-gray-200 p-6 min-h-[60vh] overflow-auto">
            <div ref={docxHostRef} />
            {error && <p className="text-red-600 text-sm mt-4">{error}</p>}
          </div>
        )}

        {mode === 'ready' && isImage && (
          <div className="bg-white rounded-xl border border-gray-200 p-4 flex justify-center">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={url} alt="Document" className="max-w-full max-h-[85vh] object-contain rounded-lg" />
          </div>
        )}

        {mode === 'ready' && isAudio && (
          <div className="bg-white rounded-xl border border-gray-200 p-8 text-center">
            <div className="text-4xl mb-4">🎵</div>
            <audio controls src={url} className="w-full max-w-lg mx-auto" />
          </div>
        )}

        {mode === 'ready' && isVideo && (
          <div className="bg-white rounded-xl border border-gray-200 p-4">
            <video controls src={url} className="w-full rounded-lg" />
          </div>
        )}

        {mode === 'ready' && isText && <TextViewer url={url} ext={ext} />}

        {mode === 'ready' && !isPdf && !isDocx && !isImage && !isAudio && !isVideo && !isText && (
          <div className="bg-white rounded-xl border border-gray-200 p-10 text-center">
            <div className="text-4xl mb-3">📄</div>
            <p className="text-gray-700 mb-1">This format (<b>{ext || 'unknown'}</b>) can't be previewed in the browser.</p>
            <p className="text-gray-500 text-sm mb-5">Download it and open with the NotesCache app or a compatible app.</p>
            <a
              href={url}
              download
              className="inline-block px-5 py-2.5 bg-indigo-600 text-white rounded-xl font-medium hover:bg-indigo-700 transition"
            >
              Download file
            </a>
          </div>
        )}
      </div>
    </main>
  )
}

function TextViewer({ url, ext }: { url: string; ext: string }) {
  const [text, setText] = useState('')
  const [err, setErr] = useState('')

  useEffect(() => {
    fetch(url)
      .then((r) => (r.ok ? r.text() : Promise.reject(new Error('HTTP ' + r.status))))
      .then(setText)
      .catch((e: unknown) => setErr(e instanceof Error ? e.message : 'Failed to load'))
  }, [url])

  if (err) return <p className="text-red-600 text-sm">{err}</p>
  return (
    <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <pre className="p-5 text-sm whitespace-pre-wrap break-words max-h-[85vh] overflow-auto font-mono">
        {text || 'Loading…'}
      </pre>
    </div>
  )
}

export default function ViewPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-gray-50 flex items-center justify-center text-gray-500">Loading…</div>}>
      <ViewerContent />
    </Suspense>
  )
}
