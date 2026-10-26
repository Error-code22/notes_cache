import { supabase } from './auth'

export type SupportConfig = {
  whatsapp: string
  email: string
}

/** Reads the support channels the admin edits in the app's Help & Support page. */
export async function getSupportConfig(): Promise<SupportConfig> {
  const { data } = await supabase
    .from('app_config')
    .select('key,value')
    .in('key', ['support_whatsapp', 'support_email'])

  const values: Record<string, string> = {}
  for (const row of data ?? []) {
    const item = row as { key?: string; value?: string | null }
    if (item.key) values[item.key] = item.value ?? ''
  }

  return {
    whatsapp: values.support_whatsapp ?? '',
    email: values.support_email ?? '',
  }
}

/**
 * WhatsApp click-to-chat. With no number it opens WhatsApp's contact picker,
 * which is the safest fallback when a student has not shared a number.
 */
export function whatsappUrl(phone: string, message: string): string {
  const digits = phone.replace(/\D/g, '')
  const text = encodeURIComponent(message)
  return digits ? `https://wa.me/${digits}?text=${text}` : `https://wa.me/?text=${text}`
}
