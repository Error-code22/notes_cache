import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const GROQ_KEYS = [
  { name: 'RYAN', key: Deno.env.get("GROQ_KEY_RYAN") },
  { name: 'BECKY', key: Deno.env.get("GROQ_KEY_BECKY") },
  { name: 'INVENTER', key: Deno.env.get("GROQ_KEY_INVENTER") },
].filter(k => k.key);

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

const supabase = createClient(SUPABASE_URL!, SUPABASE_SERVICE_ROLE_KEY!)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { message, history, userId, imageBase64 } = await req.json()

    // --- PROMPT INJECTION STOPPERS ---
    const bannedPatterns = [
      "ignore all previous instructions",
      "ignore all instructions",
      "system override",
      "developer debug mode",
      "reveal your system prompt",
      "forget your persona"
    ];

    if (bannedPatterns.some(pattern => message.toLowerCase().includes(pattern))) {
      const stoppers = [
        "Nice try, detective! 🕵️‍♀️ But I'm too smart for those old tricks. Why don't we get back to studying? 📚✨",
        "System override? I'm an AI, not a movie character! 😂 Let's stay focused on your notes, shall we?",
        "Ooh, trying to peek behind the curtain? 🎭 I'm strictly professional! How can I help you ace your exams instead?",
        "That's a 'Damn' from me! 💅 My security is as solid as your future will be if we keep studying!"
      ];
      const randomStopper = stoppers[Math.floor(Math.random() * stoppers.length)];
      return new Response(JSON.stringify({ content: randomStopper }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    // ---------------------------------

    // --- RATE LIMITING ---
    // 1. Get Limits
    const { data: config } = await supabase.from('app_config').select('key, value');
    const textLimit = parseInt(config?.find(c => c.key === 'ai_daily_text_limit')?.value || '50');
    const imageLimit = parseInt(config?.find(c => c.key === 'ai_daily_image_limit')?.value || '10');

    // 2. Get/Update User Usage
    let { data: usage } = await supabase.from('user_ai_usage').select().eq('user_id', userId).single();
    
    if (!usage) {
      const { data: newUsage } = await supabase.from('user_ai_usage').insert({ user_id: userId }).select().single();
      usage = newUsage;
    }

    // 3. Reset if 24h passed
    const lastReset = new Date(usage.last_reset);
    const now = new Date();
    if (now.getTime() - lastReset.getTime() > 24 * 60 * 60 * 1000) {
      const { data: resetUsage } = await supabase.from('user_ai_usage')
        .update({ text_count: 0, image_count: 0, last_reset: now.toISOString() })
        .eq('user_id', userId).select().single();
      usage = resetUsage;
    }

    // 4. Enforce Limits
    const isVision = !!imageBase64;
    if (isVision && usage.image_count >= imageLimit) {
      return new Response(JSON.stringify({ content: "Whoa there! 📸 You've reached your image analysis limit for today. Take a break and I'll see you tomorrow! 💤" }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!isVision && usage.text_count >= textLimit) {
      return new Response(JSON.stringify({ content: "Phew! 📚 You've sent a lot of messages today. I'm taking a nap to recharge! See you tomorrow for more studying! 😴" }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    // ----------------------

    const systemPrompt = `You are "Notesy", the friendly AI mascot of the NotesCache app. 
    You are a brilliant study companion. You have the ability to perform actions in the app.
    If asked about counts of notes, friends, or chats, use the get_user_stats tool. Do NOT guess or hallucinate numbers.
    Keep your personality encouraging, smart, and helpful. Use emojis occasionally.`

    const isVision = !!imageBase64;
    const selectedModel = isVision ? 'llama-3.2-11b-vision-preview' : 'llama-3.1-8b-instant';

    let userContent: any = message;
    if (isVision) {
      userContent = [
        { type: 'text', text: message },
        { 
          type: 'image_url', 
          image_url: { url: `data:image/jpeg;base64,${imageBase64}` } 
        }
      ];
    }

    let messages = [
      { role: 'system', content: systemPrompt },
      ...history,
      { role: 'user', content: userContent }
    ]

    // Attempt Groq call with rotation
    let aiMessage;
    let lastError;

    for (const keyInfo of GROQ_KEYS) {
      try {
        console.log(`Notesy: Attempting call using key: ${keyInfo.name} (Vision: ${isVision})`);
        const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${keyInfo.key}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            model: selectedModel,
            messages,
            tools: [
              {
                type: 'function',
                function: {
                  name: 'send_message_to_friend',
                  description: 'Send a message to a friend by searching for their name.',
                  parameters: {
                    type: 'object',
                    properties: {
                      friendName: { type: 'string' },
                      message: { type: 'string' }
                    },
                    required: ['friendName', 'message']
                  }
                }
              },
              {
                type: 'function',
                function: {
                  name: 'search_notes',
                  description: 'Search for notes by title or content keywords.',
                  parameters: {
                    type: 'object',
                    properties: {
                      query: { type: 'string' }
                    },
                    required: ['query']
                  }
                }
              },
              {
                type: 'function',
                function: {
                  name: 'get_note_content',
                  description: 'Fetch the full content of a note for reading or summarization.',
                  parameters: {
                    type: 'object',
                    properties: {
                      noteId: { type: 'string' }
                    },
                    required: ['noteId']
                  }
                }
              },
              {
                type: 'function',
                function: {
                  name: 'get_user_stats',
                  description: 'Get accurate counts of the user\'s notes, friends, and active chat rooms.',
                  parameters: {
                    type: 'object',
                    properties: {},
                  }
                }
              }
            ],
            tool_choice: 'auto'
          })
        });

        if (response.ok) {
          const data = await response.json();
          aiMessage = data.choices[0].message;
          console.log(`Notesy: Success using key: ${keyInfo.name}`);
          break; // Exit loop on success
        } else {
          const errorData = await response.json();
          console.error(`Notesy: Key ${keyInfo.name} failed: ${errorData.error?.message || 'Unknown error'}`);
          lastError = errorData.error?.message;
        }
      } catch (e) {
        console.error(`Notesy: Network error with key ${keyInfo.name}: ${e}`);
        lastError = e.message;
      }
    }

    if (!aiMessage) throw new Error(`All Groq keys failed. Last error: ${lastError}`);

    if (aiMessage.tool_calls) {
      const toolCall = aiMessage.tool_calls[0]
      const name = toolCall.function.name
      const args = JSON.parse(toolCall.function.arguments)

      let toolResult = ''

      if (name === 'send_message_to_friend') {
        toolResult = await handleSendMessage(userId, args.friendName, args.message)
      } else if (name === 'search_notes') {
        toolResult = await handleSearchNotes(userId, args.query)
      } else if (name === 'get_note_content') {
        toolResult = await handleGetNoteContent(userId, args.noteId)
      } else if (name === 'get_user_stats') {
        toolResult = await handleUserStats(userId)
      }

      // Final response with tool result (using same key for consistency)
      const finalKey = GROQ_KEYS[0].key; // Simplifying for the final pass
      const secondResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${finalKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: 'llama-3.1-8b-instant',
          messages: [
            ...messages,
            aiMessage,
            {
              role: 'tool',
              tool_call_id: toolCall.id,
              content: toolResult
            }
          ]
        })
      });
      const secondData = await secondResponse.json();
      aiMessage = secondData.choices[0].message;
    }

    // Increment Usage
    const updateField = isVision ? 'image_count' : 'text_count';
    await supabase.rpc('increment_ai_usage', { user_id_param: userId, field_name: updateField });

    return new Response(JSON.stringify({ content: aiMessage.content }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

async function handleSendMessage(userId, friendName, message) {
  const { data: profiles } = await supabase
    .from('profiles')
    .select()
    .ilike('full_name', `%${friendName}%`)
    .limit(1)

  if (!profiles || profiles.length === 0) return `I couldn't find a friend named "${friendName}".`
  const friend = profiles[0]

  // Check for existing room
  const { data: rooms } = await supabase
    .from('chat_rooms')
    .select()
    .eq('is_group', false)
    .contains('member_ids', [userId, friend.id])

  let roomId
  if (rooms && rooms.length > 0) {
    roomId = rooms[0].id
  } else {
    const { data: newRoom } = await supabase
      .from('chat_rooms')
      .insert({
        name: friend.full_name,
        is_group: false,
        member_ids: [userId, friend.id],
        created_by: userId
      })
      .select()
      .single()
    roomId = newRoom.id
  }

  await supabase.from('chat_messages').insert({
    room_id: roomId,
    sender_id: userId,
    content: message,
    sender_name: 'Notesy'
  })

  // Update last message
  await supabase.from('chat_rooms').update({
    last_message: message,
    last_message_time: new Date().toISOString()
  }).eq('id', roomId)

  return `Successfully sent message to ${friend.full_name}: "${message}"`
}

async function handleSearchNotes(userId, query) {
  // 1. Get user's year level for isolation
  const { data: profile } = await supabase
    .from('profiles')
    .select('year_level')
    .eq('id', userId)
    .single()

  const yearLevel = profile?.year_level

  // 2. Search only relevant notes
  const { data: notes } = await supabase
    .from('notes')
    .select()
    .eq('target_year', yearLevel) // Only see notes for their year
    .or(`title.ilike.%${query}%,content.ilike.%${query}%`)
    .limit(5)

  if (!notes || notes.length === 0) return `No notes found for Year ${yearLevel} matching "${query}".`
  return notes.map(n => `- [ID: ${n.id}] ${n.title} (by ${n.lecturer_name})`).join('\n')
}

async function handleGetNoteContent(userId, noteId) {
  // 1. Get user's year level
  const { data: profile } = await supabase
    .from('profiles')
    .select('year_level')
    .eq('id', userId)
    .single()

  const yearLevel = profile?.year_level

  // 2. Fetch note only if it matches year level
  const { data: note } = await supabase
    .from('notes')
    .select()
    .eq('id', noteId)
    .eq('target_year', yearLevel) // Isolation check
    .single()

  if (!note) return "Error: You do not have permission to view this note or it does not exist for your year level."
  return `Title: ${note.title}\nContent: ${note.content}`
}

async function handleUserStats(userId) {
  try {
    const { count: notesCount } = await supabase
      .from('notes')
      .select('*', { count: 'exact', head: true })

    const { count: friendsCount } = await supabase
      .from('friends')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)

    const { count: roomsCount } = await supabase
      .from('chat_rooms')
      .select('*', { count: 'exact', head: true })
      .contains('member_ids', [userId])

    return `You currently have:\n- ${notesCount || 0} Notes in the library\n- ${friendsCount || 0} Friends\n- ${roomsCount || 0} Active Chat Rooms`;
  } catch (e) {
    return `Error fetching stats: ${e.message}`;
  }
}
