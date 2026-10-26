// Generates a password-recovery link for an admin to send over WhatsApp.
//
// Why this exists: the student-facing recovery email can land in spam or be
// rejected by a browser. An admin can identify the student from the WhatsApp
// request and hand them a fresh link. The service-role key must never reach
// the Flutter binary, so the admin API call happens here.
//
// Caller: signed-in admin only. The gateway verifies the JWT; this function
// also checks the caller's profile role before touching the admin API.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  })
}

function isAdmin(role: unknown): boolean {
  return (
    typeof role === 'string' &&
    role
      .toLowerCase()
      .split(',')
      .map((part) => part.trim())
      .includes('admin')
  )
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed.' }, 405)
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    if (!supabaseUrl || !anonKey || !serviceKey) {
      console.error('admin-reset-link: Supabase environment is incomplete')
      return json({ error: 'Reset link service is not configured.' }, 500)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return json({ error: 'Authentication required.' }, 401)
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser()
    if (userError || !user) {
      return json({ error: 'Authentication required.' }, 401)
    }

    const adminClient = createClient(supabaseUrl, serviceKey)
    const { data: profile, error: profileError } = await adminClient
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle()

    if (profileError) {
      console.error('admin-reset-link: profile lookup failed', profileError.message)
      return json({ error: 'Could not verify admin access.' }, 500)
    }
    if (!isAdmin(profile?.role)) {
      return json({ error: 'Admin access required.' }, 403)
    }

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>
    const email =
      typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''

    if (
      !email ||
      email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
    ) {
      return json({ error: 'Enter a valid student email address.' }, 400)
    }

    // Supabase preserves redirect_to query parameters, so the reset page can
    // still prefill the support email if the generated link expires.
    const redirectTo =
      `https://notescache.netlify.app/reset?email=${encodeURIComponent(email)}`

    const { data, error: linkError } = await adminClient.auth.admin.generateLink({
      type: 'recovery',
      email,
      options: { redirectTo },
    })

    if (linkError) {
      console.error('admin-reset-link: generateLink failed', linkError.message)
      const notFound = /not found|no user/i.test(linkError.message)
      return json(
        {
          error: notFound
            ? 'No NotesCache account uses that email.'
            : 'Could not generate a reset link. Try again.',
        },
        notFound ? 404 : 400,
      )
    }

    const link = data?.properties?.action_link
    if (!link) {
      console.error('admin-reset-link: generateLink returned no action link')
      return json({ error: 'Could not generate a reset link. Try again.' }, 500)
    }

    console.log(
      `admin-reset-link: admin=${user.id} target=${data.user?.id ?? 'unknown'}`,
    )
    return json({
      email: data.user?.email ?? email,
      link,
      expiresInSeconds: 3600,
    })
  } catch (error) {
    console.error('admin-reset-link error', error)
    return json({ error: 'Could not generate a reset link. Try again.' }, 500)
  }
})
