# Blink Mini Live View Solution

## The Problem
Blink Mini cameras use a proprietary protocol called **IMMIS** (Immediate Media Streaming) instead of standard RTSP. The blinkpy library's livestream proxy connects but receives 0 bytes because the subscription handshake is failing.

## Quick Start (Working Solution)

### Step 1: Install Dependencies
```bash
pip install fastapi uvicorn blinkpy aiohttp aiofiles
```

### Step 2: Authenticate (if you don't have blink_token.json)
```bash
python3 explore_cameras.py
```
- Enter your email/password
- Enter the 2FA code from your email
- Token will be saved to `blink_token.json`

### Step 3: Run the Working Solution
```bash
python3 working_solution.py
```

### Step 4: Open Browser
Go to: http://localhost:8000

## What Each File Does

| File | Purpose |
|------|---------|
| `working_solution.py` | **USE THIS** - Web dashboard with Record-and-Play + Snapshot modes |
| `blink_diagnostic.py` | Diagnostic tool - run this to see exactly why streaming fails |
| `app_v2.py` | Enhanced FastAPI app with multiple streaming strategies |
| `blink_live_stream_solution.py` | Deep IMMIS protocol testing tool |
| `explore_cameras.py` | Authentication and camera exploration script |

## Why True Live Streaming Doesn't Work

The IMMIS protocol requires:
1. TLS connection to Blink's streaming server
2. A specific JSON subscription payload
3. Proprietary framing for video data

The problem is that Blink has likely changed the subscription format, and blinkpy's payload is being rejected (server accepts connection but sends 0 bytes).

## Workarounds That DO Work

### 1. Record-and-Play (Most Reliable)
- Records a ~10 second clip
- Downloads and plays it
- ~15 second delay but always works

### 2. Rapid Snapshot Mode
- Takes snapshots every 1-2 seconds
- Shows as slideshow-style "video"
- ~1 FPS but real-time

### 3. Use Official Blink App
- The official app uses a closed-source SDK
- Always works but no browser access

## Running the Diagnostic

To understand exactly what's failing:
```bash
python3 blink_diagnostic.py
```

This will:
1. Test your authentication
2. Find your cameras
3. Get the liveview URL
4. Test the IMMIS connection with multiple payload formats
5. Test blinkpy's proxy
6. Give recommendations

## Troubleshooting

### Token Expired
```
Run: python3 explore_cameras.py
```

### No Cameras Found
- Check your Blink account has cameras
- Make sure they're online in the official app

### 0 Bytes from Proxy
This is the core issue - IMMIS handshake failing. Use the workarounds above.

### FFmpeg Errors
Install FFmpeg:
```bash
# macOS
brew install ffmpeg

# Ubuntu/Debian
sudo apt install ffmpeg

# Windows
# Download from https://ffmpeg.org/download.html
```

## Technical Details

### IMMIS URL Format
```
immis://lv-z1.immedia-semi.com:443/session_id_here
```

### Expected Subscription Payload (what blinkpy sends)
```json
{
  "type": "subscribe",
  "session": "session_id",
  "auth_token": "your_token",
  "account_id": 123456,
  "camera_id": 789,
  "network_id": 456
}
```

### What's Happening
1. Connection succeeds ✅
2. TLS handshake succeeds ✅
3. Subscription sent ✅
4. Server accepts but sends nothing ❌

The server is likely expecting a different payload format that we haven't reverse-engineered yet.

## Contributing

If you figure out the correct IMMIS subscription format, please share it with the blinkpy project:
https://github.com/fronzbot/blinkpy/issues
