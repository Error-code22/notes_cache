'use client'

import { useEffect, useRef, useState, useCallback } from 'react'
import * as pdfjsLib from 'pdfjs-dist'

pdfjsLib.GlobalWorkerOptions.workerSrc = `//cdnjs.cloudflare.com/ajax/libs/pdf.js/${pdfjsLib.version}/pdf.worker.min.mjs`

export default function PdfJsViewer({ url }: { url: string }) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [totalPages, setTotalPages] = useState(0)
  const [currentPage, setCurrentPage] = useState(1)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const pdfRef = useRef<pdfjsLib.PDFDocumentProxy | null>(null)

  const renderPage = useCallback(async (pageNum: number) => {
    if (!pdfRef.current || !containerRef.current) return
    try {
      const page = await pdfRef.current.getPage(pageNum)
      const container = containerRef.current
      const parentWidth = container.clientWidth || 800
      const viewport = page.getViewport({ scale: 1 })
      const scale = parentWidth / viewport.width
      const scaledViewport = page.getViewport({ scale })

      // Clear previous canvases
      container.innerHTML = ''

      const canvas = document.createElement('canvas')
      canvas.width = scaledViewport.width
      canvas.height = scaledViewport.height
      canvas.style.width = '100%'
      canvas.style.height = 'auto'
      canvas.className = 'rounded-lg shadow-md'

      const ctx = canvas.getContext('2d')
      if (ctx) {
        await page.render({ canvasContext: ctx, viewport: scaledViewport, canvas } as any).promise
      }
      container.appendChild(canvas)
    } catch (e) {
      setError(`Failed to render page ${pageNum}`)
    }
  }, [])

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        setLoading(true)
        const loadingTask = pdfjsLib.getDocument({ url })
        const pdf = await loadingTask.promise
        if (cancelled) return
        pdfRef.current = pdf
        setTotalPages(pdf.numPages)
        setCurrentPage(1)
        setLoading(false)
        await renderPage(1)
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : 'Failed to load PDF')
          setLoading(false)
        }
      }
    })()
    return () => { cancelled = true }
  }, [url, renderPage])

  useEffect(() => {
    if (!loading && !error && pdfRef.current) {
      renderPage(currentPage)
    }
  }, [currentPage, loading, error, renderPage])

  if (error) {
    return (
      <div className="text-center py-16 text-red-500">
        <p className="font-medium">{error}</p>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="h-[80vh] rounded-xl border border-gray-200 bg-white flex items-center justify-center text-gray-400 text-sm">
        Loading PDF…
      </div>
    )
  }

  return (
    <div className="flex flex-col items-center gap-3">
      {/* Page navigation */}
      <div className="flex items-center gap-3 bg-white dark:bg-[#1C1C1E] rounded-xl border border-gray-200 dark:border-white/10 px-4 py-2 sticky top-16 z-10">
        <button
          onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
          disabled={currentPage <= 1}
          className="px-3 py-1 rounded-lg text-sm font-medium bg-indigo-600 text-white disabled:opacity-40 disabled:cursor-not-allowed hover:bg-indigo-700 transition"
        >
          Prev
        </button>
        <span className="text-sm font-medium text-gray-700 dark:text-gray-200">
          Page {currentPage} / {totalPages}
        </span>
        <button
          onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
          disabled={currentPage >= totalPages}
          className="px-3 py-1 rounded-lg text-sm font-medium bg-indigo-600 text-white disabled:opacity-40 disabled:cursor-not-allowed hover:bg-indigo-700 transition"
        >
          Next
        </button>
      </div>

      {/* Rendered page(s) */}
      <div ref={containerRef} className="w-full" />
    </div>
  )
}
