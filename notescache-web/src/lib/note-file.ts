const SUPABASE_URL = (process.env.NEXT_PUBLIC_SUPABASE_URL || '').replace(/\/$/, '')
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || ''

type NoteFileMeta = {
  url?: string | null
  download_url?: string | null
  chunks?: Array<{ chunk_index: number; size?: number }>
}

/**
 * Resolve a note's original file to something the browser can open.
 *
 * Signed R2/Cloudinary URLs are returned directly. R2 proxy and Telegram
 * chunk URLs require the caller's JWT, so those are fetched here and exposed
 * as a same-origin blob URL for the viewer.
 */
export async function resolveNoteAssetUrl(noteId: string, token: string): Promise<string | null> {
  if (!SUPABASE_URL || !SUPABASE_ANON || !token) return null

  const headers = {
    apikey: SUPABASE_ANON,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }

  try {
    const metaRes = await fetch(`${SUPABASE_URL}/functions/v1/note-file`, {
      method: 'POST',
      headers,
      body: JSON.stringify({ note_id: noteId }),
    })
    if (!metaRes.ok) return null
    const meta = (await metaRes.json()) as NoteFileMeta

    if (meta.url) return meta.url
    if (!meta.download_url) return null

    const authHeaders = { apikey: SUPABASE_ANON, Authorization: `Bearer ${token}` }

    if (Array.isArray(meta.chunks) && meta.chunks.length > 0) {
      const parts: BlobPart[] = []
      const ordered = [...meta.chunks].sort((a, b) => a.chunk_index - b.chunk_index)
      for (const chunk of ordered) {
        const url = new URL(meta.download_url)
        url.searchParams.set('chunk', String(chunk.chunk_index))
        const res = await fetch(url.toString(), { headers: authHeaders })
        if (!res.ok) return null
        parts.push(await res.blob())
      }
      return URL.createObjectURL(new Blob(parts))
    }

    const res = await fetch(meta.download_url, { headers: authHeaders })
    if (!res.ok) return null
    return URL.createObjectURL(await res.blob())
  } catch {
    return null
  }
}
