# Quota Analysis: Groq Free Tier (100 Students) 📐🛡️

## The Vision Quota (Llama 3.2 11B)
- **Daily Limit per Key**: ~1,000 requests
- **Total Capacity (3 Keys)**: 3,000 requests
- **Expected Max Load (100 students x 10 images)**: 1,000 requests
- **Margin**: 200% headroom.

## The Text Quota (Llama 3.1 8B)
- **Daily Limit per Key**: ~14,400 requests
- **Total Capacity (3 Keys)**: 43,200 requests
- **Expected Max Load (100 students x 50 messages)**: 5,000 requests
- **Margin**: 800% headroom.

## Key Rotation Logic
Our `notesy` Edge Function automatically rotates through the three keys (Ryan, Becky, Inventer). If one key hits a rate limit, it fails over to the next one, ensuring that no single student's usage "breaks" the app for everyone else.

**Verdict**: Your current limits are perfectly optimized for your 100-student baseline.
