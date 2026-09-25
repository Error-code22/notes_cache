// send-push — server-driven FCM notifications.
//
// Triggered by a Database Webhook on chat_messages INSERT (and manually for
// notes / app_updates). Looks up the recipient's FCM tokens from the
// device_tokens table and sends via the Firebase Admin SDK.
//
// Required secret (Edge Function secret, NOT repo env):
//   FIREBASE_SERVICE_ACCOUNT_JSON  — the whole service-account JSON file
//                                    downloaded from Firebase console
//                                    (Project settings → Service accounts).
//
// Payload (POST JSON):
//   { "userId": "...", "title": "...", "body": "...", "data": { ... } }
//   { "userIds": ["..."], ... }   // broadcast to several users
//   { "all": true, ... }          // everyone with a registered token
//
// When invoked by the Database Webhook (chat_messages), payload is Supabase's
// { type, table, record, ... } — we translate it automatically.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FIREBASE_SA = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");

const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

// ---------------------------------------------------------------------------
// Firebase Admin (lazy import so the function still starts if the secret is
// missing — it will just return a clear error instead of crashing).
// ---------------------------------------------------------------------------
let messaging: any = null;
async function getMessaging() {
  if (messaging) return messaging;
  if (!FIREBASE_SA) throw new Error("FIREBASE_SERVICE_ACCOUNT_JSON secret is not set");
  const { initializeApp, cert, getApps } = await import(
    "npm:firebase-admin@12/app"
  );
  const { getMessaging: gm } = await import("npm:firebase-admin@12/messaging");
  const sa = JSON.parse(FIREBASE_SA);
  const app = getApps().length
    ? getApps()[0]
    : initializeApp({ credential: cert(sa) });
  messaging = gm(app);
  return messaging;
}

// ---------------------------------------------------------------------------
// Translate incoming payload into { userIds, title, body, data }
// ---------------------------------------------------------------------------
type PushRequest = {
  userIds: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
  /** raw chat_messages record — must be re-verified against the DB */
  chatRecord?: any;
};

function parseRequest(reqBody: any): PushRequest | null {
  // Supabase Database Webhook shape: { type: "INSERT", table, record, ... }
  if (reqBody?.type === "INSERT" && reqBody?.table === "chat_messages") {
    const r = reqBody.record;
    if (!r?.content || !r?.room_id || !r?.id) return null;
    return {
      // userIds resolved later — room members minus sender
      userIds: [`room:${r.room_id}:sender:${r.sender_id}`],
      title: `New Message from ${r.sender_name ?? "someone"}`,
      body: String(r.content).slice(0, 200),
      data: { kind: "chat", room_id: String(r.room_id) },
      chatRecord: r,
    };
  }

  // Direct invocation shape
  if (reqBody?.userId || reqBody?.userIds || reqBody?.all) {
    const userIds: string[] = reqBody.all
      ? ["*"]
      : reqBody.userIds ?? [reqBody.userId];
    return {
      userIds,
      title: String(reqBody.title ?? "NotesCache"),
      body: String(reqBody.body ?? ""),
      data: reqBody.data && typeof reqBody.data === "object"
        ? Object.fromEntries(Object.entries(reqBody.data).map(([k, v]) => [k, String(v)]))
        : undefined,
    };
  }
  return null;
}

// ---------------------------------------------------------------------------
// Resolve FCM tokens for user ids ("*" = all rows)
// ---------------------------------------------------------------------------
async function resolveTokens(userIds: string[]): Promise<string[]> {
  let targets = userIds;

  // Chat-message webhook sentinel: expand to room members minus the sender
  if (targets.length === 1 && targets[0].startsWith("room:")) {
    const m = targets[0].match(/^room:(.+):sender:(.+)$/);
    if (!m) return [];
    const [, roomId, senderId] = m;
    const { data: room, error } = await supabase
      .from("chat_rooms")
      .select("member_ids")
      .eq("id", roomId)
      .single();
    if (error || !room) return [];
    targets = (room.member_ids as string[]).filter((id) => id !== senderId);
    if (targets.length === 0) return [];
  }

  let query = supabase.from("device_tokens").select("token, last_seen_at");
  if (!(targets.length === 1 && targets[0] === "*")) {
    query = query.in("user_id", targets);
  }
  const { data, error } = await query;
  if (error) throw new Error(`device_tokens query failed: ${error.message}`);
  // Drop tokens not seen for 60 days (likely dead devices)
  const cutoff = Date.now() - 60 * 24 * 60 * 60 * 1000;
  return (data ?? [])
    .filter((t: any) => !t.last_seen_at || new Date(t.last_seen_at).getTime() > cutoff)
    .map((t: any) => t.token);
}

// ---------------------------------------------------------------------------
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Auth: three accepted callers, in order of trust —
  //  1. service role key (manual/admin calls)
  //  2. the DB-generated webhook secret (chat_messages INSERT trigger)
  //  3. a logged-in user JWT — may only trigger pushes for a message
  //     they themselves sent (client-side fallback).
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");

  const { data: secretRow } = await supabase
    .from("push_webhook_secrets")
    .select("secret")
    .limit(1)
    .maybeSingle();
  const webhookSecret = secretRow?.secret ?? "";

  let caller: "service" | "webhook" | "user" | null = null;
  let userId: string | null = null;
  if (token && token === SERVICE_KEY) {
    caller = "service";
  } else if (webhookSecret && token === webhookSecret) {
    caller = "webhook";
  } else if (token) {
    try {
      const { data, error } = await supabase.auth.getUser(token);
      if (!error && data?.user) {
        caller = "user";
        userId = data.user.id;
      }
    } catch { /* fall through to unauthorized */ }
  }
  if (!caller) {
    return new Response(JSON.stringify({ ok: false, error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json().catch(() => null);
    const push = parseRequest(body);
    if (!push) {
      return new Response(JSON.stringify({ ok: false, error: "unrecognized payload" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // ------------------------------------------------------------------
    // Verification — the payload is never trusted as-is.
    // ------------------------------------------------------------------
    let dedupeKey: string | null = null;

    if (push.chatRecord) {
      const r = push.chatRecord;
      // a) The message must exist exactly as claimed (blocks forged records)
      const { data: msg } = await supabase
        .from("chat_messages")
        .select("id, room_id, sender_id, content")
        .eq("id", r.id)
        .maybeSingle();
      if (
        !msg ||
        msg.room_id !== r.room_id ||
        msg.sender_id !== r.sender_id ||
        msg.content !== r.content
      ) {
        return new Response(JSON.stringify({ ok: false, error: "record not verified" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
      // b) A user caller may only push for messages they themselves sent
      if (caller === "user" && userId !== msg.sender_id) {
        return new Response(JSON.stringify({ ok: false, error: "not your message" }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        });
      }
      dedupeKey = `chat:${msg.id}`;
    } else if (caller === "user") {
      // c) Direct payload from a user — self-notification only
      if (push.userIds.includes("*") || push.userIds.some((id) => id !== userId)) {
        return new Response(JSON.stringify({ ok: false, error: "self-only" }), {
          status: 403,
          headers: { "Content-Type": "application/json" },
        });
      }
    }

    // d) Exactly one push per event (trigger and client fallback may both fire)
    if (dedupeKey) {
      const { error: dupErr } = await supabase
        .from("push_sent")
        .insert({ key: dedupeKey });
      if (dupErr) {
        if (dupErr.code === "23505") {
          return new Response(JSON.stringify({ ok: true, sent: 0, reason: "already sent" }), {
            headers: { "Content-Type": "application/json" },
          });
        }
        throw new Error(`push_sent insert failed: ${dupErr.message}`);
      }
      // opportunistic prune of week-old keys
      await supabase
        .from("push_sent")
        .delete()
        .lt("sent_at", new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString());
    }

    const tokens = await resolveTokens(push.userIds);
    if (tokens.length === 0) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: "no tokens" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const m = await getMessaging();
    const res = await m.sendEachForMulticast({
      tokens,
      notification: { title: push.title, body: push.body },
      data: push.data,
      android: {
        priority: "high",
        notification: { channelId: "notescache_main", sound: "default" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    });

    // Purge invalid/unregistered tokens so we stop sending to dead devices
    const dead: string[] = [];
    res.responses.forEach((r: any, i: number) => {
      const code = r.error?.code ?? "";
      if (
        code.includes("registration-token-not-registered") ||
        code.includes("invalid-registration-token")
      ) {
        dead.push(tokens[i]);
      }
    });
    if (dead.length) {
      await supabase.from("device_tokens").delete().in("token", dead);
    }

    return new Response(
      JSON.stringify({ ok: true, sent: res.successCount, failed: res.failureCount, purged: dead.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("send-push error:", e);
    return new Response(
      JSON.stringify({ ok: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
