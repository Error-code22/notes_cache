# Groq Quota Deep-Dive: Bandwidth vs. Cost 📡🛡️

For the Groq Free Tier, "charging" refers to your **Quota Consumption**, not monetary cost.

## The Three "Speedometers"
1. **RPD (Requests Per Day)**: How many times you call the API.
2. **RPM (Requests Per Minute)**: How fast you are calling the API.
3. **TPM (Tokens Per Minute)**: The "weight" or complexity of your requests.

## Why Images are "Heavy"
- **Text**: A typical student question is ~50-100 tokens.
- **Image**: A single Llama 3.2 Vision request counts as ~1,100 to 1,600 tokens because the model has to "process" the pixels into data.

## Our Strategy
By limiting users to **10 images and 50 texts**, we are managing your **TPM (Tokens Per Minute)**. This ensures that even if 10 students all upload an image at the exact same minute, we don't exceed the Groq "pipe" capacity and get a `429: Too Many Requests` error.

**Verdict**: Your app is configured to stay within the high-speed "Express Lane" of Groq's free tier.
