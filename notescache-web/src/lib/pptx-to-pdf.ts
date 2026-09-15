'use client'

import JSZip from 'jszip'
import { jsPDF } from 'jspdf'

export type PptxSlide = {
  texts: string[]
  /** data URLs for embedded images on this slide */
  images: string[]
}

/**
 * Parse a .pptx (zip) into ordered slides with text runs + image data URLs.
 * Works fully in the browser — no conversion service.
 */
export async function parsePptxFile(file: File | Blob | ArrayBuffer): Promise<PptxSlide[]> {
  const buf = file instanceof ArrayBuffer ? file : await file.arrayBuffer()
  const zip = await JSZip.loadAsync(buf)

  const slidePaths = Object.keys(zip.files)
    .filter((p) => /^ppt\/slides\/slide\d+\.xml$/i.test(p))
    .sort((a, b) => {
      const na = Number(a.match(/slide(\d+)/i)?.[1] || 0)
      const nb = Number(b.match(/slide(\d+)/i)?.[1] || 0)
      return na - nb
    })

  // Load media once as data URLs
  const media: Record<string, string> = {}
  const mediaPaths = Object.keys(zip.files).filter((p) => /^ppt\/media\//i.test(p))
  for (const p of mediaPaths.slice(0, 60)) {
    try {
      const b64 = await zip.files[p].async('base64')
      const name = p.toLowerCase()
      const mime = name.endsWith('.png') ? 'image/png'
        : name.endsWith('.gif') ? 'image/gif'
        : name.endsWith('.webp') ? 'image/webp'
        : 'image/jpeg'
      media[p] = `data:${mime};base64,${b64}`
    } catch { /* skip corrupt media */ }
  }

  const slides: PptxSlide[] = []
  for (const path of slidePaths) {
    const xml = await zip.files[path].async('string')
    const texts = extractSlideTexts(xml)

    const images: string[] = []
    const relsPath = path.replace(/slides\/slide(\d+)\.xml$/i, 'slides/_rels/slide$1.xml.rels')
    const rels = zip.files[relsPath]
    if (rels) {
      const relXml = await rels.async('string')
      const relRe = /Target="([^"]+)"/g
      let rm: RegExpExecArray | null
      while ((rm = relRe.exec(relXml))) {
        const target = rm[1]
        if (!/\.(png|jpe?g|gif|webp)$/i.test(target)) continue
        const base = target.split('/').pop() || ''
        const key = Object.keys(media).find((k) => k.endsWith('/' + base) || k.endsWith(base))
        if (key) images.push(media[key])
      }
    }
    slides.push({ texts, images })
  }
  return slides
}

function decodeXml(s: string): string {
  return s
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
}

/**
 * Pull real text runs from slide XML.
 * Must NOT match <a:tbl>, <a:tc>, etc. — only <a:t> and <a:t ...attrs>.
 */
export function extractSlideTexts(xml: string): string[] {
  const texts: string[] = []
  // \s after t, or immediately close — never a longer tag name like a:tbl
  const re = /<a:t(?:\s[^>]*)?>([\s\S]*?)<\/a:t>/g
  let m: RegExpExecArray | null
  while ((m = re.exec(xml))) {
    const raw = m[1]
    // Skip if the capture still looks like markup (bad parse / nested junk)
    if (raw.includes('</') || raw.includes('<p:') || raw.includes('<a:bodyPr')) continue
    const t = decodeXml(raw)
      .replace(/<[^>]+>/g, '') // strip any stray tags
      .replace(/\s+/g, ' ')
      .trim()
    if (t && t.length < 2000) texts.push(t)
  }
  return texts
}

function loadImage(src: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => resolve(null)
    img.src = src
  })
}

/**
 * Build a landscape PDF from parsed slides (text + images).
 * Not pixel-perfect PowerPoint, but a real multi-page PDF for web/in-app viewing.
 */
export type ConvertProgress = {
  phase: 'parse' | 'render' | 'done'
  current: number
  total: number
}

export async function slidesToPdfBlob(
  slides: PptxSlide[],
  title = 'Slides',
  onProgress?: (p: ConvertProgress) => void,
): Promise<Blob> {
  // 16:9 landscape, mm units
  const pdf = new jsPDF({ orientation: 'landscape', unit: 'mm', format: [280, 157.5] })
  const pageW = 280
  const pageH = 157.5
  const margin = 12
  const total = slides.length || 1

  for (let i = 0; i < slides.length; i++) {
    onProgress?.({ phase: 'render', current: i + 1, total })
    if (i > 0) pdf.addPage([pageW, pageH], 'landscape')
    const s = slides[i]

    // Header
    pdf.setFontSize(9)
    pdf.setTextColor(130, 130, 130)
    pdf.text(`${title}  ·  ${i + 1}/${slides.length}`, margin, 10)

    let y = 22

    // Images (up to 2, stacked/side-by-side if small)
    for (const src of s.images.slice(0, 3)) {
      const img = await loadImage(src)
      if (!img) continue
      const maxW = pageW - margin * 2
      const maxH = 55
      const scale = Math.min(maxW / img.width, maxH / img.height, 1)
      const w = img.width * scale
      const h = img.height * scale
      if (y + h > pageH - 20) break
      try {
        pdf.addImage(src, src.startsWith('data:image/png') ? 'PNG' : 'JPEG', margin, y, w, h)
        y += h + 6
      } catch { /* skip undrawable */ }
    }

    // Text body
    pdf.setTextColor(20, 20, 20)
    pdf.setFontSize(14)
    const lines: string[] = []
    for (const t of s.texts) {
      const wrapped = pdf.splitTextToSize(t, pageW - margin * 2) as string[]
      lines.push(...wrapped)
    }

    if (lines.length === 0) {
      pdf.setFontSize(11)
      pdf.setTextColor(150, 150, 150)
      pdf.text('(no text on this slide)', margin, y + 4)
      continue
    }

    // First line larger as a stand-in for slide titles
    pdf.setFontSize(16)
    pdf.text(lines[0], margin, y + 4)
    y += 10

    pdf.setFontSize(11)
    for (const line of lines.slice(1)) {
      if (y > pageH - 12) break
      pdf.text(line, margin, y)
      y += 5.2
    }
  }

  onProgress?.({ phase: 'done', current: total, total })
  return pdf.output('blob')
}

/** Full pipeline: pptx File → PDF Blob */
export async function pptxFileToPdf(
  file: File | Blob,
  title?: string,
  onProgress?: (p: ConvertProgress) => void,
): Promise<Blob> {
  onProgress?.({ phase: 'parse', current: 0, total: 1 })
  const slides = await parsePptxFile(file)
  if (!slides.length) throw new Error('No slides found in PPTX')
  const name = title || ('name' in file ? file.name : 'Slides').replace(/\.(pptx?|ppsx?)$/i, '')
  return slidesToPdfBlob(slides, name, onProgress)
}

/** Chrome PDF viewer: full width, no thumbnail sidebar. */
export function pdfViewerUrl(u: string): string {
  const hash = '#pagemode=none&navpanes=0&view=FitH&toolbar=1'
  if (u.startsWith('blob:') || u.startsWith('data:')) return u + hash
  return u + (u.includes('#') ? '&' : '#') + hash.slice(1)
}
