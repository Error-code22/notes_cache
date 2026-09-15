'use client'

// Shared client helpers for the web replica of the Flutter app.

export function extFromName(name: string): string {
  const m = (name || '').match(/\.([a-z0-9]{1,5})$/i)
  return m ? m[1].toLowerCase() : ''
}

export function categoryFromName(name: string): string {
  const t = (name || '').toLowerCase()
  if (t.endsWith('.pdf')) return 'pdf'
  if (t.endsWith('.ppt') || t.endsWith('.pptx') || t.endsWith('.ppsx') || t.endsWith('.pps')) return 'slides'
  if (t.endsWith('.doc') || t.endsWith('.docx')) return 'document'
  if (t.endsWith('.xls') || t.endsWith('.xlsx') || t.endsWith('.csv')) return 'spreadsheet'
  if (t.endsWith('.mp4') || t.endsWith('.mov') || t.endsWith('.mkv')) return 'video'
  if (t.endsWith('.mp3') || t.endsWith('.wav') || t.endsWith('.m4a')) return 'audio'
  if (t.endsWith('.jpg') || t.endsWith('.jpeg') || t.endsWith('.png') || t.endsWith('.webp')) return 'image'
  if (t.endsWith('.txt') || t.endsWith('.md')) return 'text'
  return 'document'
}

export function noteType(title: string, category?: string): string {
  const t = (title || '').toLowerCase()
  const c = (category || '').toLowerCase()
  if (t.endsWith('.pdf') || c === 'pdf') return 'pdf'
  if (t.endsWith('.ppt') || t.endsWith('.pptx') || t.endsWith('.ppsx') || t.endsWith('.pps') || c === 'slides') return 'ppt'
  if (t.endsWith('.doc') || t.endsWith('.docx') || c === 'document') return 'doc'
  if (t.endsWith('.xls') || t.endsWith('.xlsx') || t.endsWith('.csv') || c === 'spreadsheet') return 'xls'
  if (t.endsWith('.mp4') || t.endsWith('.mov') || t.endsWith('.mkv') || c === 'video') return 'vid'
  if (t.endsWith('.mp3') || t.endsWith('.wav') || t.endsWith('.m4a') || c === 'audio') return 'aud'
  if (t.endsWith('.jpg') || t.endsWith('.jpeg') || t.endsWith('.png') || t.endsWith('.webp') || c === 'image') return 'img'
  if (/\.(py|js|ts|dart|html|json|css|java|cpp|c|rs|go)$/i.test(t)) return 'code'
  if (t.endsWith('.txt') || t.endsWith('.md') || c === 'text') return 'txt'
  return 'other'
}

export const TYPE_META: Record<string, { label: string; color: string }> = {
  pdf: { label: 'PDF', color: '#EF5350' },
  doc: { label: 'DOC', color: '#42A5F5' },
  ppt: { label: 'PPT', color: '#FFA726' },
  xls: { label: 'XLS', color: '#66BB6A' },
  vid: { label: 'VID', color: '#5C6BC0' },
  aud: { label: 'AUD', color: '#EC407A' },
  img: { label: 'IMG', color: '#AB47BC' },
  code: { label: 'CODE', color: '#78909C' },
  txt: { label: 'TXT', color: '#26A69A' },
  other: { label: 'FILE', color: '#90A4AE' },
}

export function isSlideExt(ext: string): boolean {
  const e = (ext || '').replace(/^\./, '').toLowerCase()
  return e === 'pptx' || e === 'ppt' || e === 'ppsx' || e === 'pps' || e === 'pub'
}

export function viewUrl(n: { title?: string; gdrive_id?: string; category?: string; pdf_url?: string | null }): string {
  // PPTX/Publisher: prefer the pre-converted PDF (same path as the Flutter app)
  const titleExt = extFromName(n.title || '')
  let ext = titleExt
  if (!ext) {
    const c = (n.category || '').toLowerCase()
    if (c === 'pdf') ext = 'pdf'
    else if (c === 'slides') ext = 'pptx'
    else if (c === 'document') ext = 'docx'
    else if (c === 'image') ext = 'jpg'
    else if (c === 'video') ext = 'mp4'
    else if (c === 'audio') ext = 'mp3'
    else if (c === 'spreadsheet') ext = 'xlsx'
  }

  if (isSlideExt(ext) && n.pdf_url) {
    return `/view?url=${encodeURIComponent(n.pdf_url)}&ext=pdf`
  }

  return `/view?url=${encodeURIComponent(n.gdrive_id || '')}&ext=${encodeURIComponent(ext)}`
}

export function parseRoles(role?: string | null): string[] {
  return String(role || '')
    .split(',')
    .map((r) => r.trim())
    .filter(Boolean)
    .map((r) => r.toUpperCase())
}

export function hasStaffVisibility(role?: string | null): boolean {
  const roles = parseRoles(role)
  return roles.some((r) => r === 'ADMIN' || r === 'LECTURER' || r === 'MODERATOR')
}

export function todayKey(): string {
  return new Date().toISOString().slice(0, 10)
}

export function fileToBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const result = String(reader.result || '')
      const comma = result.indexOf(',')
      resolve(comma >= 0 ? result.slice(comma + 1) : result)
    }
    reader.onerror = () => reject(reader.error)
    reader.readAsDataURL(file)
  })
}

/** Minimal markdown: bold, italic, code, links, lists, headers, paragraphs. */
export function renderMarkdownLite(text: string): string {
  const esc = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  let html = esc(text)
  html = html.replace(/`([^`]+)`/g, '<code>$1</code>')
  html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  html = html.replace(/(^|[^*])\*([^*]+)\*/g, '$1<em>$2</em>')
  html = html.replace(/^### (.+)$/gm, '<h4>$1</h4>')
  html = html.replace(/^## (.+)$/gm, '<h3>$1</h3>')
  html = html.replace(/^# (.+)$/gm, '<h2>$1</h2>')
  html = html.replace(/^(?:- |\* )(.+)$/gm, '<li>$1</li>')
  html = html.replace(/(<li>[\s\S]*?<\/li>)(?:\n(?=<li>))/g, '$1')
  html = html.replace(/((?:<li>.*?<\/li>\n?)+)/g, '<ul>$1</ul>')
  html = html
    .split(/\n{2,}/)
    .map((block) => {
      const t = block.trim()
      if (!t) return ''
      if (t.startsWith('<h') || t.startsWith('<ul') || t.startsWith('<code')) return t
      return `<p>${t.replace(/\n/g, '<br/>')}</p>`
    })
    .join('\n')
  return html
}
