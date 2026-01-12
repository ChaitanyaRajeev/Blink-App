#!/usr/bin/env python3
"""
BLINK MINI WORKING SOLUTION
===========================

This is a WORKING solution for viewing Blink Mini cameras in a browser.

Since the IMMIS live streaming protocol is problematic, this uses two
reliable workarounds:

1. RECORD-AND-PLAY: Records a clip, downloads it, displays it
2. RAPID SNAPSHOT: Takes snapshots every 1-2 seconds for near-live view

Usage:
    pip install fastapi uvicorn blinkpy aiohttp aiofiles
    python3 working_solution.py

Then open: http://localhost:8000
"""

import asyncio
import json
import os
import logging
import tempfile
import base64
from datetime import datetime
from typing import Optional, Dict
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
import aiohttp
import aiofiles

from blinkpy.blinkpy import Blink
from blinkpy.auth import Auth

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOKEN_FILE = "blink_token.json"
CLIPS_DIR = tempfile.mkdtemp(prefix="blink_clips_")

blink: Optional[Blink] = None
session: Optional[aiohttp.ClientSession] = None


async def init_blink():
    global blink, session
    
    if not os.path.exists(TOKEN_FILE):
        logger.error(f"Token file not found: {TOKEN_FILE}")
        return
    
    async with aiofiles.open(TOKEN_FILE, 'r') as f:
        auth_data = json.loads(await f.read())
    
    session = aiohttp.ClientSession()
    blink = Blink(session=session)
    blink.auth = Auth(auth_data, no_prompt=True)
    
    try:
        await blink.start()
        logger.info(f"✅ Connected! Cameras: {len(blink.cameras)}")
    except Exception as e:
        logger.error(f"Auth failed: {e}")
        blink = None


async def shutdown():
    if session:
        await session.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_blink()
    yield
    await shutdown()


app = FastAPI(title="Blink Mini Viewer", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.get("/", response_class=HTMLResponse)
async def home():
    if not blink:
        return HTMLResponse("<h1>Not authenticated</h1><p>Run explore_cameras.py first</p>")
    return HTMLResponse(DASHBOARD_HTML)


@app.get("/api/cameras")
async def list_cameras():
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    cameras = []
    for name, cam in blink.cameras.items():
        cameras.append({
            "name": name,
            "id": str(cam.camera_id),
            "type": cam.camera_type or cam.product_type or "unknown"
        })
    return {"cameras": cameras}


@app.get("/api/cameras/{camera_id}/snapshot")
async def get_snapshot(camera_id: str):
    """Get current snapshot from camera"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    # Refresh to get latest
    await blink.refresh(force=True)
    
    if camera.image_from_cache:
        return Response(content=camera.image_from_cache, media_type="image/jpeg")
    
    raise HTTPException(404, "No snapshot available")


@app.post("/api/cameras/{camera_id}/snap")
async def take_snapshot(camera_id: str):
    """Request new snapshot"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    try:
        await camera.snap_picture()
        await asyncio.sleep(2)
        await blink.refresh(force=True)
        return {"success": True}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.post("/api/cameras/{camera_id}/record")
async def record_clip(camera_id: str):
    """Record a new clip and return its path"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    try:
        logger.info(f"Recording from {camera.name}...")
        await camera.record()
        
        # Wait for recording
        await asyncio.sleep(12)
        
        # Get clip
        for _ in range(5):
            await blink.refresh(force=True)
            if camera.clip:
                break
            await asyncio.sleep(2)
        
        if not camera.clip:
            return {"success": False, "error": "No clip available yet"}
        
        # Download clip
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"clip_{camera_id}_{timestamp}.mp4"
        filepath = os.path.join(CLIPS_DIR, filename)
        
        await camera.video_to_file(filepath)
        
        if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
            return {
                "success": True,
                "clip_url": f"/api/clips/{filename}",
                "size": os.path.getsize(filepath)
            }
        
        return {"success": False, "error": "Clip download failed"}
        
    except Exception as e:
        logger.error(f"Record error: {e}")
        raise HTTPException(500, str(e))


@app.get("/api/clips/{filename}")
async def get_clip(filename: str):
    """Serve recorded clip"""
    filepath = os.path.join(CLIPS_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(404, "Clip not found")
    return FileResponse(filepath, media_type="video/mp4")


@app.websocket("/ws/live/{camera_id}")
async def websocket_live(websocket: WebSocket, camera_id: str):
    """WebSocket-based rapid snapshot stream"""
    await websocket.accept()
    
    if not blink:
        await websocket.close(1008, "Not authenticated")
        return
    
    camera = _find_camera(camera_id)
    if not camera:
        await websocket.close(1008, "Camera not found")
        return
    
    logger.info(f"WebSocket stream started for {camera.name}")
    
    try:
        frame_count = 0
        while True:
            # Get fresh snapshot
            try:
                await camera.snap_picture()
            except:
                pass
            
            await asyncio.sleep(0.5)
            await blink.refresh(force=True)
            
            if camera.image_from_cache:
                img_b64 = base64.b64encode(camera.image_from_cache).decode()
                await websocket.send_json({
                    "type": "frame",
                    "frame": frame_count,
                    "data": img_b64
                })
                frame_count += 1
            
            await asyncio.sleep(1)  # ~1 FPS
            
    except WebSocketDisconnect:
        logger.info("WebSocket disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")


def _find_camera(camera_id: str):
    for name, cam in blink.cameras.items():
        if str(cam.camera_id) == camera_id:
            return cam
    return None


DASHBOARD_HTML = """
<!DOCTYPE html>
<html>
<head>
    <title>Blink Mini Viewer</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { 
            font-family: -apple-system, sans-serif;
            background: #0f0f1a; 
            color: white; 
            padding: 20px;
            min-height: 100vh;
        }
        h1 { 
            text-align: center; 
            margin-bottom: 30px;
            background: linear-gradient(90deg, #3b82f6, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .cameras { 
            display: grid; 
            grid-template-columns: repeat(auto-fill, minmax(450px, 1fr));
            gap: 20px;
            max-width: 1200px;
            margin: 0 auto;
        }
        .camera-card {
            background: #1a1a2e;
            border-radius: 12px;
            overflow: hidden;
            border: 1px solid #333;
        }
        .camera-header {
            padding: 15px;
            background: #252540;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .camera-name { font-weight: 600; }
        .camera-type { font-size: 0.8rem; color: #888; }
        .video-container {
            position: relative;
            width: 100%;
            aspect-ratio: 16/9;
            background: #000;
        }
        .video-container img, .video-container video {
            width: 100%;
            height: 100%;
            object-fit: contain;
        }
        .live-badge {
            position: absolute;
            top: 10px;
            left: 10px;
            background: #ef4444;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: bold;
            display: none;
        }
        .live-badge.active { display: block; animation: pulse 2s infinite; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:0.5} }
        .controls {
            padding: 15px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        .btn {
            padding: 10px 16px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 0.9rem;
            transition: all 0.2s;
        }
        .btn-primary { background: #3b82f6; color: white; }
        .btn-primary:hover { background: #2563eb; }
        .btn-secondary { background: #374151; color: white; }
        .btn-secondary:hover { background: #4b5563; }
        .btn:disabled { opacity: 0.5; cursor: wait; }
        .status {
            padding: 10px 15px;
            background: #252540;
            font-size: 0.85rem;
            color: #888;
        }
        .loading { text-align: center; padding: 40px; color: #666; }
    </style>
</head>
<body>
    <h1>📹 Blink Mini Viewer</h1>
    <div class="cameras" id="cameras">
        <div class="loading">Loading cameras...</div>
    </div>

    <script>
        let cameras = [];
        let websockets = {};
        
        async function init() {
            const resp = await fetch('/api/cameras');
            const data = await resp.json();
            cameras = data.cameras;
            render();
        }
        
        function render() {
            const container = document.getElementById('cameras');
            
            if (!cameras.length) {
                container.innerHTML = '<div class="loading">No cameras found</div>';
                return;
            }
            
            container.innerHTML = cameras.map(cam => `
                <div class="camera-card" id="cam-${cam.id}">
                    <div class="camera-header">
                        <div>
                            <div class="camera-name">${cam.name}</div>
                            <div class="camera-type">${cam.type}</div>
                        </div>
                    </div>
                    <div class="video-container">
                        <img id="img-${cam.id}" src="/api/cameras/${cam.id}/snapshot" 
                             onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22640%22 height=%22360%22><rect fill=%22%23222%22 width=%22100%25%22 height=%22100%25%22/><text x=%2250%25%22 y=%2250%25%22 fill=%22%23666%22 text-anchor=%22middle%22>Click Refresh</text></svg>'">
                        <video id="video-${cam.id}" style="display:none" controls autoplay></video>
                        <div class="live-badge" id="live-${cam.id}">● LIVE</div>
                    </div>
                    <div class="controls">
                        <button class="btn btn-primary" onclick="startLive('${cam.id}')">▶ Live View</button>
                        <button class="btn btn-secondary" onclick="recordClip('${cam.id}')">🔴 Record</button>
                        <button class="btn btn-secondary" onclick="refresh('${cam.id}')">🔄 Refresh</button>
                        <button class="btn btn-secondary" onclick="stopLive('${cam.id}')" style="display:none" id="stop-${cam.id}">⏹ Stop</button>
                    </div>
                    <div class="status" id="status-${cam.id}">Ready</div>
                </div>
            `).join('');
        }
        
        function setStatus(id, msg) {
            document.getElementById('status-' + id).textContent = msg;
        }
        
        async function refresh(id) {
            setStatus(id, 'Refreshing...');
            await fetch('/api/cameras/' + id + '/snap', {method: 'POST'});
            document.getElementById('img-' + id).src = '/api/cameras/' + id + '/snapshot?t=' + Date.now();
            setStatus(id, 'Refreshed');
        }
        
        function startLive(id) {
            setStatus(id, 'Starting live view...');
            
            // WebSocket for rapid snapshots
            const ws = new WebSocket(`ws://${location.host}/ws/live/${id}`);
            websockets[id] = ws;
            
            ws.onopen = () => {
                setStatus(id, 'Live (snapshot mode ~1fps)');
                document.getElementById('live-' + id).classList.add('active');
                document.getElementById('stop-' + id).style.display = 'inline-block';
            };
            
            ws.onmessage = (e) => {
                const data = JSON.parse(e.data);
                if (data.type === 'frame') {
                    document.getElementById('img-' + id).src = 'data:image/jpeg;base64,' + data.data;
                }
            };
            
            ws.onclose = () => {
                setStatus(id, 'Disconnected');
                document.getElementById('live-' + id).classList.remove('active');
                document.getElementById('stop-' + id).style.display = 'none';
            };
            
            ws.onerror = () => setStatus(id, 'Connection error');
        }
        
        function stopLive(id) {
            if (websockets[id]) {
                websockets[id].close();
                delete websockets[id];
            }
            setStatus(id, 'Stopped');
        }
        
        async function recordClip(id) {
            const btn = event.target;
            btn.disabled = true;
            setStatus(id, 'Recording (~15s)...');
            
            try {
                const resp = await fetch('/api/cameras/' + id + '/record', {method: 'POST'});
                const data = await resp.json();
                
                if (data.success) {
                    setStatus(id, 'Playing clip...');
                    
                    // Show video
                    const img = document.getElementById('img-' + id);
                    const video = document.getElementById('video-' + id);
                    
                    img.style.display = 'none';
                    video.style.display = 'block';
                    video.src = data.clip_url;
                    video.play();
                    
                    video.onended = () => {
                        video.style.display = 'none';
                        img.style.display = 'block';
                        setStatus(id, 'Ready');
                    };
                } else {
                    setStatus(id, 'Error: ' + (data.error || 'Unknown'));
                }
            } catch (e) {
                setStatus(id, 'Error: ' + e.message);
            }
            
            btn.disabled = false;
        }
        
        init();
    </script>
</body>
</html>
"""

if __name__ == "__main__":
    import uvicorn
    
    print("\n" + "=" * 60)
    print("  BLINK MINI VIEWER")
    print("  Working solution using Record-and-Play + Snapshots")
    print("=" * 60)
    print("\n📋 Requirements:")
    print("   1. blink_token.json (run explore_cameras.py first)")
    print("   2. pip install fastapi uvicorn blinkpy aiohttp aiofiles")
    print("\n🌐 Starting server at http://localhost:8000")
    print("=" * 60 + "\n")
    
    uvicorn.run(app, host="0.0.0.0", port=8000)
