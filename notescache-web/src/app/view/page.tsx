'use client'

import { useEffect, useRef, useState, Suspense } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import JSZip from 'jszip'
import { pdfViewerUrl } from '../../lib/pptx-to-pdf'

/** Prefer Cloudinary inline delivery so browsers render instead of download. */
function inlineUrl(u: string): string {
  try {
    const parsed = new URL(u)
    if (parsed.hostname.includes('cloudinary.com') && parsed.pathname.includes('/raw/upload/') && !parsed.pathname.includes('/fl_inline/')) {
      parsed.pathname = parsed.pathname.replace('/raw/upload/', '/raw/upload/fl_inline/')
      return parsed.toString()
    }
  } catch { /* ignore */ }
  return u
}

async function fetchFileBlob(url: string, preferInline = false): Promise<Blob> {
  const candidates = preferInline ? [inlineUrl(url), url] : [url, inlineUrl(url)]
  let lastErr: Error | null = null
  for (const u of candidates) {
    try {
      const res = await fetch(u)
      if (res.ok) return await res.blob()
      lastErr = new Error(`HTTP ${res.status}`)
    } catch (e) {
      lastErr = e instanceof Error ? e : new Error('Network error')
    }
  }
  throw lastErr || new Error('Failed to download file')
}

function resolveExt(url: string, extParam: string): string {
  let e = ''
  if (extParam.startsWith('.')) e = extParam.toLowerCase()
  else if (extParam) e = '.' + extParam.toLowerCase()
  if (!e) {
    try {
      const path = new URL(url).pathname
      const last = path.substring(path.lastIndexOf('/') + 1)
      const dot = last.lastIndexOf('.')
      if (dot > 0 && last.length - dot <= 6) e = last.substring(dot).toLowerCase()
    } catch { /* ignore */ }
  }
  if (e === '.ppsx' || e === '.pps') return '.pptx'
  return e
}

/** Extract text (and optional image blobs) from a pptx zip. */
async function parsePptx(buf: ArrayBuffer): Promise<{ slides: { texts: string[]; images: string[] }[] }> {
  const zip = await JSZip.loadAsync(buf)
  const slideFiles = Object.keys(zip.files)
    .filter((p) => /^ppt\/slides\/slide\d+\.xml$/i.test(p))
    .sort((a, b) => {
      const na = Number(a.match(/slide(\d+)/i)?.[1] || 0)
      const nb = Number(b.match(/slide(\d+)/i)?.[1] || 0)
      return na - nb
    })

  const media: Record<string, string> = {}
  const mediaPaths = Object.keys(zip.files).filter((p) => /^ppt\/media\//i.test(p))
  for (const p of mediaPaths.slice(0, 40)) {
    try {
      const blob = await zip.files[p].async('blob')
      media[p] = URL.createObjectURL(blob)
    } catch { /* skip */ }
  }

  const slides: { texts: string[]; images: string[] }[] = []
  for (const path of slideFiles) {
    const xml = await zip.files[path].async('string')
    const texts: string[] = []
    // Only <a:t> / <a:t attrs> — NOT <a:tbl> etc.
    const re = /<a:t(?:\s[^>]*)?>([\s\S]*?)<\/a:t>/g
    let m: RegExpExecArray | null
    while ((m = re.exec(xml))) {
      const raw = m[1]
      if (raw.includes('</') || raw.includes('<p:') || raw.includes('<a:bodyPr')) continue
      const t = raw
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/<[^>]+>/g, '')
        .replace(/\s+/g, ' ')
        .trim()
      if (t && t.length < 2000) texts.push(t)
    }
    // Best-effort: any media referenced in this slide's rels
    const relsPath = path.replace(/slides\/slide(\d+)\.xml$/i, 'slides/_rels/slide$1.xml.rels')
    const images: string[] = []
    const rels = zip.files[relsPath]
    if (rels) {
      const relXml = await rels.async('string')
      const relRe = /Target="([^"]+)"/g
      let rm: RegExpExecArray | null
      while ((rm = relRe.exec(relXml))) {
        const target = rm[1]
        if (!/\.(png|jpe?g|gif|webp|emf|wmf)$/i.test(target)) continue
        const resolved = target.startsWith('../') ? 'ppt/' + target.replace(/^\.\.\//, '') : `ppt/slides/${target}`
        const key = Object.keys(media).find((k) => k.endsWith(resolved.replace(/^ppt\//, '')) || k === resolved || k.endsWith(target.replace(/^\.\.\//, '')))
        const found = key || Object.keys(media).find((k) => k.includes(target.split('/').pop() || ''))
        if (found && media[found]) images.push(media[found])
      }
    }
    slides.push({ texts, images })
  }
  return { slides }
}

function ViewerContent() {
  const params = useSearchParams()
  const router = useRouter()
  const url = params.get('url') || ''
  const extParam = (params.get('ext') || '').toLowerCase()
  const [mode, setMode] = useState<'loading' | 'ready' | 'error'>('loading')
  const [error, setError] = useState('')
  const [ext, setExt] = useState('')
  const [fileBlobUrl, setFileBlobUrl] = useState('')
  const [loadErr, setLoadErr] = useState('')
  const [pptxSlides, setPptxSlides] = useState<{ texts: string[]; images: string[] }[] | null>(null)
  const docxHostRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!url) {
      setMode('error')
      setError('No document URL provided.')
      return
    }
    try { new URL(url) } catch {
      setMode('error')
      setError('That URL looks invalid.')
      return
    }
    setExt(resolveExt(url, extParam))
    setMode('ready')
  }, [url, extParam])

  const isPdf = ext === '.pdf'
  const isDocx = ext === '.docx'
  const isXlsx = ext === '.xlsx' || ext === '.xls' || ext === '.csv'
  const isSlide = ext === '.pptx' || ext === '.ppt'
  const isLegacyDoc = ext === '.doc'
  const isImage = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'].includes(ext)
  const isAudio = ['.mp3', '.wav', '.m4a', '.aac', '.ogg', '.flac'].includes(ext)
  const isVideo = ['.mp4', '.mov', '.mkv', '.webm', '.m4v'].includes(ext)
  const isText = ['.txt', '.md', '.json', '.xml', '.html', '.log', '.py', '.js', '.ts', '.dart', '.sql', '.sh', '.yaml', '.yml', '.css'].includes(ext)

  const needsBlob = isPdf || isDocx || isXlsx

  // PDF / DOCX / XLSX blob load — PDF MUST get application/pdf or the browser downloads
  useEffect(() => {
    if (mode !== 'ready' || !needsBlob || !url) return
    let objectUrl = ''
    let cancelled = false
    ;(async () => {
      try {
        setLoadErr('')
        const blob = await fetchFileBlob(url, isPdf)
        if (cancelled) return
        let out: Blob
        if (isPdf) {
          out = new Blob([blob], { type: 'application/pdf' })
        } else if (isDocx) {
          out = new Blob([blob], { type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' })
        } else if (ext === '.csv') {
          out = new Blob([blob], { type: 'text/csv' })
        } else {
          out = new Blob([blob], { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
        }
        objectUrl = URL.createObjectURL(out)
        setFileBlobUrl(objectUrl)
      } catch (e) {
        if (!cancelled) setLoadErr(e instanceof Error ? e.message : 'Failed to load file')
      }
    })()
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [mode, ext, url, needsBlob, isPdf, isDocx])

  // Local PPTX parse (text + embedded images) — does not need Office Online
  useEffect(() => {
    if (mode !== 'ready' || !isSlide || !url || ext === '.ppt') return
    let cancelled = false
    ;(async () => {
      try {
        setLoadErr('')
        const blob = await fetchFileBlob(url)
        const buf = await blob.arrayBuffer()
        const { slides } = await parsePptx(buf)
        if (!cancelled) {
          if (!slides.length) throw new Error('No slides found in file.')
          setPptxSlides(slides)
        }
      } catch (e) {
        if (!cancelled) setLoadErr(e instanceof Error ? e.message : 'Failed to parse PPTX')
      }
    })()
    return () => { cancelled = true }
  }, [mode, ext, url, isSlide])

  // DOCX render from blob
  useEffect(() => {
    if (mode !== 'ready' || !isDocx || !fileBlobUrl) return
    let cancelled = false
    ;(async () => {
      try {
        const mod = await import('docx-preview')
        const res = await fetch(fileBlobUrl)
        const blob = await res.blob()
        if (cancelled || !docxHostRef.current) return
        docxHostRef.current.innerHTML = ''
        await mod.renderAsync(blob, docxHostRef.current, undefined, {
          inWrapper: true,
          ignoreWidth: false,
          ignoreHeight: false,
          breakPages: true,
          experimental: true,
        })
      } catch (err: unknown) {
        if (!cancelled) setLoadErr(err instanceof Error ? err.message : 'Failed to render DOCX')
      }
    })()
    return () => { cancelled = true }
  }, [mode, isDocx, fileBlobUrl])

  function goBack() {
    if (window.history.length > 1) router.back()
    else router.push('/notes')
  }

  return (
    <main className="min-h-screen bg-[#FAFAF7] dark:bg-[#121212]">
      <header className="bg-white/95 dark:bg-[#1C1C1E]/95 backdrop-blur border-b border-black/5 dark:border-white/10 sticky top-0 z-10">
        <div className="max-w-5xl mx-auto px-4 py-3 flex items-center justify-between gap-3">
          <div className="flex items-center gap-2 min-w-0">
            <button onClick={goBack} className="text-gray-400 hover:text-indigo-600 p-1 shrink-0" aria-label="Back">←</button>
            <a href="/" className="font-bold text-indigo-600 shrink-0">NotesCache</a>
          </div>
          <div className="flex items-center gap-3 min-w-0">
            <span className="text-xs text-gray-500 truncate">
              Viewing <b className="text-gray-700 dark:text-gray-200">{ext || 'file'}</b>
            </span>
            <a
              href={inlineUrl(url)}
              target="_blank"
              rel="noopener noreferrer"
              download
              className="px-3 py-1.5 border border-indigo-600 text-indigo-600 rounded-lg text-xs font-medium hover:bg-indigo-50 transition shrink-0"
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
            <p className="text-gray-700 dark:text-gray-200 font-medium">{error}</p>
            <button onClick={goBack} className="mt-4 text-indigo-600 text-sm hover:underline">← Back</button>
          </div>
        )}

        {mode === 'ready' && isPdf && (
          <div>
            {loadErr && <ErrBox msg={loadErr} url={url} onBack={goBack} />}
            {fileBlobUrl ? (
              <iframe
                src={isPdf ? pdfViewerUrl(fileBlobUrl) : fileBlobUrl}
                title="PDF viewer"
                className="w-full h-[88vh] rounded-xl border border-gray-200 dark:border-white/10 bg-white"
              />
            ) : !loadErr ? (
              <Placeholder label="Loading PDF…" />
            ) : null}
          </div>
        )}

        {mode === 'ready' && isDocx && (
          <div>
            {loadErr && <ErrBox msg={loadErr} url={url} onBack={goBack} />}
            {!loadErr && (
              <div className="docx-viewport bg-[#E8E8E8] dark:bg-black/20 rounded-xl border border-gray-200 dark:border-white/10 p-4 sm:p-8 min-h-[70vh] overflow-auto">
                <div ref={docxHostRef} className="docx-host mx-auto" />
                {!fileBlobUrl && <p className="text-center text-gray-400 text-sm py-8">Loading document…</p>}
              </div>
            )}
          </div>
        )}

        {mode === 'ready' && isXlsx && (
          <div>
            {loadErr && <ErrBox msg={loadErr} url={url} onBack={goBack} />}
            {fileBlobUrl && <SpreadsheetViewer blobUrl={fileBlobUrl} />}
            {!fileBlobUrl && !loadErr && <Placeholder label="Loading spreadsheet…" />}
          </div>
        )}

        {mode === 'ready' && isSlide && (
          <div>
            <div className="mb-3 rounded-xl border border-indigo-200 bg-indigo-50 dark:bg-indigo-500/10 px-4 py-3 text-sm text-indigo-800 dark:text-indigo-200">
              Slides open as <b>PDF</b> from Academic Notes (server converts via LibreOffice).
              This page is a simplified text preview if you land here directly.
            </div>
            {pptxSlides && pptxSlides.length > 0 && (
              <div className="space-y-4">
                {pptxSlides.map((s, i) => (
                  <div key={i} className="bg-white dark:bg-[#1C1C1E] border border-gray-200 dark:border-white/10 rounded-2xl p-5">
                    <div className="text-[11px] font-bold text-gray-400 mb-3">SLIDE {i + 1}</div>
                    {s.images.length > 0 && (
                      <div className="flex flex-wrap gap-2 mb-3">
                        {s.images.map((src, j) => (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img key={j} src={src} alt="" className="max-h-40 rounded-lg border border-black/5 object-contain" />
                        ))}
                      </div>
                    )}
                    {s.texts.length === 0 ? (
                      <p className="text-sm text-gray-400">No text on this slide.</p>
                    ) : (
                      <div className="space-y-1.5">
                        {s.texts.map((t, j) => (
                          <p key={j} className="text-sm text-gray-800 dark:text-gray-100 whitespace-pre-wrap">{t}</p>
                        ))}
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
            {!pptxSlides && (
              <div>{loadErr ? <ErrBox msg={loadErr} url={url} onBack={goBack} /> : <Placeholder label="Parsing slides…" />}</div>
            )}
          </div>
        )}

        {mode === 'ready' && isLegacyDoc && (
          <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 p-10 text-center">
            <p className="text-gray-700 dark:text-gray-200 mb-1">
              Legacy <b>.doc</b> can&apos;t be previewed in the browser.
            </p>
            <p className="text-gray-500 text-sm mb-4">Download it and open in Word or the NotesCache app.</p>
            <a href={inlineUrl(url)} target="_blank" rel="noopener noreferrer" className="inline-block px-5 py-2.5 bg-indigo-600 text-white rounded-xl font-medium">
              Download file
            </a>
          </div>
        )}

        {mode === 'ready' && isImage && (
          <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 p-4 flex flex-col items-center gap-3">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={url}
              alt="Document"
              className="max-w-full max-h-[85vh] object-contain rounded-lg"
              onError={(e) => {
                const el = e.currentTarget
                if (el.dataset.retried !== '1') {
                  el.dataset.retried = '1'
                  el.src = inlineUrl(url)
                } else setLoadErr('Image failed to load.')
              }}
            />
            {loadErr && <ErrBox msg={loadErr} url={url} onBack={goBack} />}
          </div>
        )}

        {mode === 'ready' && isAudio && (
          <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 p-8 text-center">
            <audio controls src={url} className="w-full max-w-lg mx-auto" />
          </div>
        )}

        {mode === 'ready' && isVideo && (
          <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 p-4">
            <video controls src={url} className="w-full rounded-lg" />
          </div>
        )}

        {mode === 'ready' && isText && (
          <div>
            {loadErr && <ErrBox msg={loadErr} url={url} onBack={goBack} />}
            {!loadErr && <TextViewer url={url} onErr={setLoadErr} />}
          </div>
        )}

        {mode === 'ready' && !isPdf && !isDocx && !isXlsx && !isSlide && !isLegacyDoc && !isImage && !isAudio && !isVideo && !isText && (
          <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 p-10 text-center">
            <p className="text-gray-700 dark:text-gray-200 mb-1">No in-browser preview for <b>{ext || 'this format'}</b>.</p>
            <a href={inlineUrl(url)} target="_blank" rel="noopener noreferrer" className="inline-block mt-3 px-5 py-2.5 bg-indigo-600 text-white rounded-xl font-medium">
              Download file
            </a>
          </div>
        )}
      </div>
    </main>
  )
}

function Placeholder({ label }: { label: string }) {
  return (
    <div className="h-[70vh] rounded-xl border border-gray-200 bg-white flex items-center justify-center text-gray-400 text-sm">
      {label}
    </div>
  )
}

function ErrBox({ msg, url, onBack }: { msg: string; url: string; onBack: () => void }) {
  return (
    <div className="mb-3 rounded-xl border border-amber-200 bg-amber-50 dark:bg-amber-500/10 px-4 py-3 text-sm text-amber-800 dark:text-amber-200">
      <p className="font-semibold mb-1">Couldn&apos;t preview</p>
      <p className="text-xs mb-2">{msg}</p>
      {url && <p className="text-[11px] break-all mb-2 opacity-80">{url}</p>}
      <div className="flex gap-3">
        {url && <a href={inlineUrl(url)} target="_blank" rel="noopener noreferrer" className="text-indigo-600 font-bold underline">Open file</a>}
        <button onClick={onBack} className="text-gray-600 underline">Go back</button>
      </div>
    </div>
  )
}

function SpreadsheetViewer({ blobUrl }: { blobUrl: string }) {
  const [sheets, setSheets] = useState<{ name: string; rows: string[][] }[]>([])
  const [active, setActive] = useState(0)
  const [err, setErr] = useState('')

  useEffect(() => {
    ;(async () => {
      try {
        const XLSX = await import('xlsx')
        const res = await fetch(blobUrl)
        const buf = await res.arrayBuffer()
        const wb = XLSX.read(buf, { type: 'array' })
        const out = wb.SheetNames.map((name) => {
          const ws = wb.Sheets[name]
          const rows = XLSX.utils.sheet_to_json<string[]>(ws, { header: 1, raw: false, defval: '' })
          return { name, rows: rows.map((r) => (Array.isArray(r) ? r.map((c) => String(c ?? '')) : [])) }
        })
        setSheets(out)
      } catch (e) {
        setErr(e instanceof Error ? e.message : 'Failed to parse spreadsheet')
      }
    })()
  }, [blobUrl])

  if (err) return <ErrBox msg={err} url="" onBack={() => window.history.back()} />
  if (!sheets.length) return <Placeholder label="Parsing spreadsheet…" />
  const sheet = sheets[Math.min(active, sheets.length - 1)]

  return (
    <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 overflow-hidden">
      {sheets.length > 1 && (
        <div className="flex gap-1 p-2 border-b border-black/5 dark:border-white/10 overflow-x-auto">
          {sheets.map((s, i) => (
            <button
              key={s.name}
              onClick={() => setActive(i)}
              className={`px-3 py-1.5 rounded-lg text-xs font-bold whitespace-nowrap ${i === active ? 'bg-indigo-600 text-white' : 'bg-gray-100 dark:bg-white/5 text-gray-600 dark:text-gray-300'}`}
            >
              {s.name}
            </button>
          ))}
        </div>
      )}
      <div className="overflow-auto max-h-[85vh]">
        <table className="text-xs border-collapse min-w-full">
          <tbody>
            {sheet.rows.slice(0, 200).map((row, ri) => (
              <tr key={ri} className={ri === 0 ? 'bg-gray-50 dark:bg-white/5 font-semibold' : ''}>
                {row.slice(0, 40).map((cell, ci) => (
                  <td key={ci} className="border border-gray-100 dark:border-white/5 px-2 py-1 whitespace-nowrap max-w-[240px] truncate text-gray-800 dark:text-gray-100">
                    {cell}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}

function TextViewer({ url, onErr }: { url: string; onErr: (m: string) => void }) {
  const [text, setText] = useState('')

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const blob = await fetchFileBlob(url)
        const t = await blob.text()
        if (!cancelled) setText(t)
      } catch (e) {
        if (!cancelled) onErr(e instanceof Error ? e.message : 'Failed to load text')
      }
    })()
    return () => { cancelled = true }
  }, [url, onErr])

  return (
    <div className="bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 overflow-hidden">
      <pre className="p-5 text-sm whitespace-pre-wrap break-words max-h-[85vh] overflow-auto font-mono text-gray-800 dark:text-gray-100">
        {text || 'Loading…'}
      </pre>
    </div>
  )
}

export default function ViewPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-[#FAFAF7] flex items-center justify-center text-gray-500">Loading…</div>}>
      <ViewerContent />
    </Suspense>
  )
}
