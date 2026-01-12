#!/usr/bin/env python3
"""
Blink Camera Dashboard v2 - Enhanced Live View
===============================================
This version properly handles the IMMIS protocol for Blink Mini cameras.

Key improvements:
1. Proper IMMIS protocol handling with multiple payload formats
2. WebSocket-based live view for browser
3. Fallback to snapshot-based "live" view
4. Better error handling and debugging
"""

import asyncio
import json
import os
import logging
import subprocess
import tempfile
import ssl
import struct
import socket
import base64
from typing import Optional, Dict, Any, AsyncGenerator
from contextlib import asynccontextmanager
from datetime import datetime
from io import BytesIO

from fastapi import FastAPI, HTTPException, Response, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, StreamingResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import aiohttp
import aiofiles

# Blinkpy imports
from blinkpy.blinkpy import Blink
from blinkpy.auth import Auth

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
TOKEN_FILE = "blink_token.json"
STATIC_DIR = "static"

# Global state
blink: Optional[Blink] = None
session: Optional[aiohttp.ClientSession] = None
auth_data: Dict[str, Any] = {}


# =============================================================================
# IMMIS Protocol Handler
# =============================================================================

class IMMISStreamHandler:
    """
    Handles IMMIS protocol for Blink Mini cameras.
    The protocol requires:
    1. TLS connection to the streaming server
    2. Sending a subscription payload
    3. Receiving framed video data
    """
    
    def __init__(self, url: str, auth_token: str, account_id: int, 
                 client_id: str, network_id: int, camera_id: int):
        self.url = url
        self.auth_token = auth_token
        self.account_id = account_id
        self.client_id = client_id
        self.network_id = network_id
        self.camera_id = camera_id
        
        # Parse URL
        self.host, self.port, self.path = self._parse_url(url)
        
        self.reader: Optional[asyncio.StreamReader] = None
        self.writer: Optional[asyncio.StreamWriter] = None
        self.connected = False
    
    def _parse_url(self, url: str):
        """Parse immis:// URL"""
        # Format: immis://host:port/path
        if url.startswith('immis://'):
            url = url[8:]
        
        if '/' in url:
            host_port, path = url.split('/', 1)
            path = '/' + path
        else:
            host_port = url
            path = '/'
        
        if ':' in host_port:
            host, port = host_port.split(':')
            port = int(port)
        else:
            host = host_port
            port = 443
        
        return host, port, path
    
    async def connect(self) -> bool:
        """Establish TLS connection"""
        logger.info(f"IMMIS: Connecting to {self.host}:{self.port}")
        
        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE
        
        try:
            self.reader, self.writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port, ssl=ssl_ctx),
                timeout=10.0
            )
            self.connected = True
            logger.info("IMMIS: Connected!")
            return True
        except Exception as e:
            logger.error(f"IMMIS: Connection failed - {e}")
            return False
    
    def _build_subscription(self) -> bytes:
        """Build subscription payload"""
        # This is the critical part - format must match Blink's expectations
        
        # Extract session from path if present
        session_id = None
        if 'session=' in self.path:
            session_id = self.path.split('session=')[-1].split('&')[0]
        
        payload = {
            "type": "subscribe",
            "session": session_id or self.path,
            "auth_token": self.auth_token,
            "account_id": self.account_id,
            "client_id": int(self.client_id) if str(self.client_id).isdigit() else self.client_id,
            "network_id": self.network_id,
            "camera_id": self.camera_id,
            "options": {
                "video_profile": "hd",
                "include_audio": False
            }
        }
        
        return json.dumps(payload, separators=(',', ':')).encode()
    
    async def start_stream(self) -> bool:
        """Send subscription to start receiving video"""
        if not self.connected:
            return False
        
        payload = self._build_subscription()
        logger.info(f"IMMIS: Sending subscription ({len(payload)} bytes)")
        
        try:
            self.writer.write(payload)
            await self.writer.drain()
            return True
        except Exception as e:
            logger.error(f"IMMIS: Subscription failed - {e}")
            return False
    
    async def read_data(self, size: int = 65536, timeout: float = 5.0) -> Optional[bytes]:
        """Read raw data from stream"""
        if not self.reader:
            return None
        
        try:
            return await asyncio.wait_for(self.reader.read(size), timeout=timeout)
        except asyncio.TimeoutError:
            return b''
        except Exception as e:
            logger.error(f"IMMIS: Read error - {e}")
            return None
    
    async def close(self):
        """Close connection"""
        if self.writer:
            self.writer.close()
            try:
                await self.writer.wait_closed()
            except:
                pass
        self.connected = False


# =============================================================================
# Application Setup
# =============================================================================

async def initialize_blink():
    """Initialize Blink connection"""
    global blink, session, auth_data
    
    if not os.path.exists(TOKEN_FILE):
        logger.warning(f"Token file not found: {TOKEN_FILE}")
        return
    
    try:
        async with aiofiles.open(TOKEN_FILE, 'r') as f:
            auth_data = json.loads(await f.read())
        
        session = aiohttp.ClientSession()
        blink = Blink(session=session)
        blink.auth = Auth(auth_data, no_prompt=True)
        
        await blink.start()
        logger.info(f"✅ Authenticated! Account: {blink.account_id}, Cameras: {len(blink.cameras)}")
        
    except Exception as e:
        logger.error(f"Blink init error: {e}")
        blink = None


async def shutdown_blink():
    """Cleanup"""
    global session
    if session:
        await session.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    await initialize_blink()
    yield
    await shutdown_blink()


# Create app
app = FastAPI(title="Blink Camera Dashboard", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

os.makedirs(STATIC_DIR, exist_ok=True)


# =============================================================================
# API Endpoints
# =============================================================================

@app.get("/", response_class=HTMLResponse)
async def root():
    """Serve dashboard with embedded live view"""
    if not blink:
        return HTMLResponse(content="""
        <html><head><title>Auth Required</title>
        <style>body{background:#0a0a0f;color:white;font-family:sans-serif;display:flex;
        align-items:center;justify-content:center;height:100vh;margin:0;}
        .box{text-align:center;padding:40px;background:#14141e;border-radius:16px;}</style>
        </head><body><div class="box"><h1>🔒 Authentication Required</h1>
        <p>Run <code>python3 explore_cameras.py</code> to authenticate first.</p>
        </div></body></html>
        """)
    
    # Return the full dashboard
    return HTMLResponse(content=DASHBOARD_HTML)


@app.get("/api/status")
async def get_status():
    """Get system status"""
    if not blink:
        return {"authenticated": False, "message": "Not authenticated"}
    return {
        "authenticated": True,
        "account_id": blink.account_id,
        "camera_count": len(blink.cameras)
    }


@app.get("/api/cameras")
async def get_cameras():
    """Get all cameras"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    cameras = []
    for name, cam in blink.cameras.items():
        cameras.append({
            "name": name,
            "camera_id": str(cam.camera_id),
            "network_id": cam.network_id,
            "camera_type": cam.camera_type or cam.product_type or "unknown",
            "thumbnail": f"/api/cameras/{cam.camera_id}/thumbnail"
        })
    return {"cameras": cameras}


@app.get("/api/cameras/{camera_id}/thumbnail")
async def get_thumbnail(camera_id: str):
    """Get camera thumbnail"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    try:
        if camera.image_from_cache:
            return Response(content=camera.image_from_cache, media_type="image/jpeg")
        
        # Try to get fresh thumbnail
        await camera.snap_picture()
        await asyncio.sleep(2)
        await blink.refresh(force=True)
        
        if camera.image_from_cache:
            return Response(content=camera.image_from_cache, media_type="image/jpeg")
        
        raise HTTPException(404, "No thumbnail available")
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/cameras/{camera_id}/liveview-url")
async def get_liveview_url(camera_id: str):
    """Get liveview URL for debugging"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    try:
        url = await camera.get_liveview()
        return {
            "url": url,
            "is_immis": url.startswith("immis://") if url else False,
            "camera_type": camera.camera_type or camera.product_type
        }
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/cameras/{camera_id}/stream")
async def stream_camera(camera_id: str):
    """
    Stream camera as MJPEG.
    This uses multiple strategies:
    1. Try RTSPS if available (older cameras)
    2. Try blinkpy's livestream proxy
    3. Fall back to rapid snapshot refresh
    """
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    async def mjpeg_stream() -> AsyncGenerator[bytes, None]:
        """Generate MJPEG stream"""
        boundary = b"--frame\r\n"
        
        # Strategy 1: Try blinkpy livestream proxy
        try:
            logger.info(f"Starting livestream for {camera.name}...")
            
            # Check camera type
            cam_type = (camera.camera_type or camera.product_type or '').lower()
            
            # Get liveview URL
            url = await camera.get_liveview()
            logger.info(f"Got liveview URL: {url[:50]}...")
            
            if url.startswith("rtsps://"):
                # Standard RTSP - use FFmpeg
                async for frame in _stream_via_ffmpeg(url):
                    yield boundary
                    yield b"Content-Type: image/jpeg\r\n\r\n"
                    yield frame
                    yield b"\r\n"
                return
            
            elif url.startswith("immis://"):
                # Try blinkpy's built-in proxy
                livestream = await camera.init_livestream()
                await livestream.start(host="127.0.0.1", port=0)
                
                # Start feeding
                feed_task = asyncio.create_task(livestream.feed())
                proxy_url = f"rtsp://127.0.0.1:{livestream.port}"
                
                try:
                    # Wait for data to start flowing
                    await asyncio.sleep(1)
                    
                    async for frame in _stream_via_ffmpeg(proxy_url):
                        yield boundary
                        yield b"Content-Type: image/jpeg\r\n\r\n"
                        yield frame
                        yield b"\r\n"
                finally:
                    feed_task.cancel()
                    livestream.stop()
                return
                
        except Exception as e:
            logger.warning(f"Livestream failed: {e}, falling back to snapshot mode")
        
        # Strategy 2: Fallback to rapid snapshots
        logger.info(f"Using snapshot fallback for {camera.name}")
        
        last_frame = None
        for _ in range(600):  # 10 minutes max
            try:
                # Get snapshot
                await camera.snap_picture()
                await asyncio.sleep(0.5)
                await blink.refresh(force=True)
                
                if camera.image_from_cache and camera.image_from_cache != last_frame:
                    last_frame = camera.image_from_cache
                    yield boundary
                    yield b"Content-Type: image/jpeg\r\n\r\n"
                    yield camera.image_from_cache
                    yield b"\r\n"
                
                await asyncio.sleep(1)  # Rate limit
                
            except Exception as e:
                logger.error(f"Snapshot error: {e}")
                await asyncio.sleep(2)
    
    return StreamingResponse(
        mjpeg_stream(),
        media_type="multipart/x-mixed-replace; boundary=frame"
    )


@app.post("/api/cameras/{camera_id}/record")
async def record_clip(camera_id: str):
    """Record a new clip"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    try:
        await camera.record()
        return {"success": True, "message": "Recording started"}
    except Exception as e:
        raise HTTPException(500, str(e))


@app.get("/api/cameras/{camera_id}/latest-clip")
async def get_latest_clip(camera_id: str):
    """Get latest recorded clip URL"""
    if not blink:
        raise HTTPException(503, "Not authenticated")
    
    camera = _find_camera(camera_id)
    if not camera:
        raise HTTPException(404, "Camera not found")
    
    await blink.refresh(force=True)
    
    if camera.clip:
        return {"clip_url": camera.clip}
    return {"clip_url": None}


@app.websocket("/ws/stream/{camera_id}")
async def websocket_stream(websocket: WebSocket, camera_id: str):
    """WebSocket-based streaming for lower latency"""
    await websocket.accept()
    
    if not blink:
        await websocket.close(code=1008, reason="Not authenticated")
        return
    
    camera = _find_camera(camera_id)
    if not camera:
        await websocket.close(code=1008, reason="Camera not found")
        return
    
    logger.info(f"WebSocket stream started for {camera.name}")
    
    try:
        while True:
            # Get latest snapshot
            await blink.refresh(force=True)
            
            if camera.image_from_cache:
                # Send as base64 encoded image
                img_b64 = base64.b64encode(camera.image_from_cache).decode()
                await websocket.send_json({
                    "type": "frame",
                    "data": img_b64,
                    "timestamp": datetime.now().isoformat()
                })
            
            await asyncio.sleep(1)  # 1 FPS for snapshots
            
    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected for {camera.name}")
    except Exception as e:
        logger.error(f"WebSocket error: {e}")


# =============================================================================
# Helper Functions
# =============================================================================

def _find_camera(camera_id: str):
    """Find camera by ID"""
    for name, cam in blink.cameras.items():
        if str(cam.camera_id) == camera_id:
            return cam
    return None


async def _stream_via_ffmpeg(url: str) -> AsyncGenerator[bytes, None]:
    """Stream video via FFmpeg and extract JPEG frames"""
    
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning"]
    
    if url.startswith("rtsps://"):
        cmd.extend(["-rtsp_transport", "tcp"])
    
    cmd.extend([
        "-i", url,
        "-f", "image2pipe",
        "-vcodec", "mjpeg",
        "-q:v", "5",
        "-r", "10",
        "-"
    ])
    
    logger.info(f"Starting FFmpeg: {' '.join(cmd[:6])}...")
    
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE
    )
    
    try:
        buffer = b""
        while True:
            chunk = await process.stdout.read(65536)
            if not chunk:
                break
            
            buffer += chunk
            
            # Find JPEG frames (start: FFD8, end: FFD9)
            while True:
                start = buffer.find(b'\xff\xd8')
                if start == -1:
                    break
                
                end = buffer.find(b'\xff\xd9', start)
                if end == -1:
                    break
                
                frame = buffer[start:end+2]
                buffer = buffer[end+2:]
                yield frame
                
    finally:
        process.terminate()
        await process.wait()


# =============================================================================
# Dashboard HTML
# =============================================================================

DASHBOARD_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Blink Camera Dashboard</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 100%);
            color: white;
            min-height: 100vh;
            padding: 20px;
        }
        
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        
        .header h1 {
            font-size: 2rem;
            background: linear-gradient(90deg, #3b82f6, #8b5cf6);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        
        .status {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8rem;
            margin-top: 10px;
        }
        
        .status.connected { background: #22c55e; }
        .status.disconnected { background: #ef4444; }
        
        .cameras-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 20px;
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .camera-card {
            background: rgba(30, 30, 50, 0.8);
            border-radius: 16px;
            overflow: hidden;
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        
        .camera-header {
            padding: 15px 20px;
            background: rgba(0, 0, 0, 0.3);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .camera-name {
            font-weight: 600;
            font-size: 1.1rem;
        }
        
        .camera-type {
            font-size: 0.8rem;
            color: rgba(255, 255, 255, 0.5);
        }
        
        .video-container {
            position: relative;
            width: 100%;
            aspect-ratio: 16/9;
            background: #000;
        }
        
        .video-container img {
            width: 100%;
            height: 100%;
            object-fit: contain;
        }
        
        .live-indicator {
            position: absolute;
            top: 10px;
            left: 10px;
            background: #ef4444;
            color: white;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 600;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.5; }
        }
        
        .controls {
            padding: 15px 20px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        .btn {
            padding: 8px 16px;
            border: none;
            border-radius: 8px;
            font-size: 0.9rem;
            cursor: pointer;
            transition: all 0.2s;
        }
        
        .btn-primary {
            background: #3b82f6;
            color: white;
        }
        
        .btn-primary:hover {
            background: #2563eb;
        }
        
        .btn-secondary {
            background: rgba(255, 255, 255, 0.1);
            color: white;
        }
        
        .btn-secondary:hover {
            background: rgba(255, 255, 255, 0.2);
        }
        
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        
        .loading {
            display: flex;
            align-items: center;
            justify-content: center;
            height: 200px;
            color: rgba(255, 255, 255, 0.5);
        }
        
        .error-message {
            background: rgba(239, 68, 68, 0.2);
            border: 1px solid #ef4444;
            padding: 10px 15px;
            border-radius: 8px;
            margin: 10px;
            font-size: 0.9rem;
        }
        
        .debug-panel {
            position: fixed;
            bottom: 20px;
            right: 20px;
            background: rgba(0, 0, 0, 0.9);
            border-radius: 8px;
            padding: 15px;
            max-width: 400px;
            max-height: 300px;
            overflow-y: auto;
            font-family: monospace;
            font-size: 0.8rem;
            display: none;
        }
        
        .debug-panel.visible { display: block; }
        
        .debug-toggle {
            position: fixed;
            bottom: 20px;
            left: 20px;
            background: rgba(255, 255, 255, 0.1);
            border: none;
            color: white;
            padding: 10px 15px;
            border-radius: 8px;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>📹 Blink Camera Dashboard</h1>
        <div class="status disconnected" id="status">Connecting...</div>
    </div>
    
    <div class="cameras-grid" id="cameras-container">
        <div class="loading">Loading cameras...</div>
    </div>
    
    <button class="debug-toggle" onclick="toggleDebug()">🐛 Debug</button>
    
    <div class="debug-panel" id="debug-panel">
        <div id="debug-log"></div>
    </div>
    
    <script>
        const API_BASE = '';
        let cameras = [];
        let streamingCameras = new Set();
        
        // Debug logging
        function log(msg) {
            console.log(msg);
            const logEl = document.getElementById('debug-log');
            logEl.innerHTML = `[${new Date().toLocaleTimeString()}] ${msg}<br>` + logEl.innerHTML;
            logEl.innerHTML = logEl.innerHTML.split('<br>').slice(0, 50).join('<br>');
        }
        
        function toggleDebug() {
            document.getElementById('debug-panel').classList.toggle('visible');
        }
        
        // Initialize
        async function init() {
            log('Initializing...');
            
            try {
                // Check status
                const status = await fetch(`${API_BASE}/api/status`).then(r => r.json());
                log(`Status: ${JSON.stringify(status)}`);
                
                const statusEl = document.getElementById('status');
                if (status.authenticated) {
                    statusEl.className = 'status connected';
                    statusEl.textContent = `Connected (${status.camera_count} cameras)`;
                } else {
                    statusEl.className = 'status disconnected';
                    statusEl.textContent = 'Not authenticated';
                    return;
                }
                
                // Load cameras
                await loadCameras();
                
            } catch (e) {
                log(`Error: ${e.message}`);
                document.getElementById('status').textContent = 'Error';
            }
        }
        
        async function loadCameras() {
            log('Loading cameras...');
            
            const resp = await fetch(`${API_BASE}/api/cameras`);
            const data = await resp.json();
            cameras = data.cameras;
            
            log(`Found ${cameras.length} camera(s)`);
            
            renderCameras();
        }
        
        function renderCameras() {
            const container = document.getElementById('cameras-container');
            
            if (cameras.length === 0) {
                container.innerHTML = '<div class="loading">No cameras found</div>';
                return;
            }
            
            container.innerHTML = cameras.map(cam => `
                <div class="camera-card" id="camera-${cam.camera_id}">
                    <div class="camera-header">
                        <div>
                            <div class="camera-name">${cam.name}</div>
                            <div class="camera-type">${cam.camera_type}</div>
                        </div>
                        <div class="camera-id">#${cam.camera_id}</div>
                    </div>
                    <div class="video-container">
                        <img id="video-${cam.camera_id}" 
                             src="${cam.thumbnail}" 
                             alt="${cam.name}"
                             onerror="this.src='data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 width=%22400%22 height=%22225%22><rect fill=%22%23333%22 width=%22100%25%22 height=%22100%25%22/><text x=%2250%25%22 y=%2250%25%22 fill=%22%23666%22 text-anchor=%22middle%22>No Preview</text></svg>'">
                        <div class="live-indicator" id="live-${cam.camera_id}" style="display:none">● LIVE</div>
                    </div>
                    <div class="controls">
                        <button class="btn btn-primary" onclick="toggleStream('${cam.camera_id}')">
                            ▶️ Start Live
                        </button>
                        <button class="btn btn-secondary" onclick="refreshSnapshot('${cam.camera_id}')">
                            📷 Snapshot
                        </button>
                        <button class="btn btn-secondary" onclick="recordClip('${cam.camera_id}')">
                            🔴 Record
                        </button>
                        <button class="btn btn-secondary" onclick="debugCamera('${cam.camera_id}')">
                            🔧 Debug
                        </button>
                    </div>
                </div>
            `).join('');
        }
        
        function toggleStream(cameraId) {
            const videoEl = document.getElementById(`video-${cameraId}`);
            const liveEl = document.getElementById(`live-${cameraId}`);
            const btn = event.target;
            
            if (streamingCameras.has(cameraId)) {
                // Stop streaming
                log(`Stopping stream for ${cameraId}`);
                const cam = cameras.find(c => c.camera_id === cameraId);
                videoEl.src = cam.thumbnail;
                liveEl.style.display = 'none';
                btn.textContent = '▶️ Start Live';
                streamingCameras.delete(cameraId);
            } else {
                // Start streaming
                log(`Starting stream for ${cameraId}`);
                videoEl.src = `${API_BASE}/api/cameras/${cameraId}/stream?t=${Date.now()}`;
                liveEl.style.display = 'block';
                btn.textContent = '⏹️ Stop Live';
                streamingCameras.add(cameraId);
            }
        }
        
        async function refreshSnapshot(cameraId) {
            log(`Refreshing snapshot for ${cameraId}`);
            const videoEl = document.getElementById(`video-${cameraId}`);
            videoEl.src = `${API_BASE}/api/cameras/${cameraId}/thumbnail?t=${Date.now()}`;
        }
        
        async function recordClip(cameraId) {
            log(`Starting recording for ${cameraId}`);
            const btn = event.target;
            btn.disabled = true;
            btn.textContent = '⏳ Recording...';
            
            try {
                await fetch(`${API_BASE}/api/cameras/${cameraId}/record`, { method: 'POST' });
                
                // Wait for recording
                await new Promise(r => setTimeout(r, 10000));
                
                // Get clip
                const clipData = await fetch(`${API_BASE}/api/cameras/${cameraId}/latest-clip`).then(r => r.json());
                
                if (clipData.clip_url) {
                    log(`Clip available: ${clipData.clip_url}`);
                    alert('Recording complete! Clip is available in Blink cloud.');
                } else {
                    log('No clip URL returned');
                }
            } catch (e) {
                log(`Record error: ${e.message}`);
            }
            
            btn.disabled = false;
            btn.textContent = '🔴 Record';
        }
        
        async function debugCamera(cameraId) {
            log(`Debugging camera ${cameraId}...`);
            
            try {
                const data = await fetch(`${API_BASE}/api/cameras/${cameraId}/liveview-url`).then(r => r.json());
                log(`Liveview URL: ${data.url}`);
                log(`Is IMMIS: ${data.is_immis}`);
                log(`Camera type: ${data.camera_type}`);
                
                document.getElementById('debug-panel').classList.add('visible');
                
            } catch (e) {
                log(`Debug error: ${e.message}`);
            }
        }
        
        // Start
        init();
    </script>
</body>
</html>
"""


# =============================================================================
# Main
# =============================================================================

if __name__ == "__main__":
    import uvicorn
    
    print("\n" + "=" * 60)
    print("  BLINK CAMERA DASHBOARD v2")
    print("  Enhanced Live View with IMMIS Support")
    print("=" * 60)
    print("\n📋 Make sure you have:")
    print("   1. blink_token.json (run explore_cameras.py first)")
    print("   2. FFmpeg installed (for video transcoding)")
    print("\n🌐 Starting server on http://localhost:8000\n")
    
    uvicorn.run("app_v2:app", host="0.0.0.0", port=8000, reload=True)
