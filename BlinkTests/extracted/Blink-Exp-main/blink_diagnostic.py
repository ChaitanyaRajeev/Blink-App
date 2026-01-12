#!/usr/bin/env python3
"""
BLINK MINI IMMIS PROTOCOL DEEP DIAGNOSTIC
==========================================

Run this on YOUR computer to diagnose why live streaming isn't working.

Usage:
    python3 blink_diagnostic.py

Requirements:
    pip install blinkpy aiohttp
"""

import asyncio
import aiohttp
import json
import ssl
import struct
import socket
import os
import sys
import logging
import traceback
from datetime import datetime
from typing import Optional, Dict, Any, Tuple, List

# Configure logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s | %(levelname)-8s | %(message)s',
    datefmt='%H:%M:%S'
)
logger = logging.getLogger(__name__)
logging.getLogger('asyncio').setLevel(logging.WARNING)


class BlinkDiagnostic:
    """Comprehensive Blink diagnostic tool"""
    
    def __init__(self, token_file: str = "blink_token.json"):
        self.token_file = token_file
        self.auth_data = {}
        self.blink = None
        self.session = None
        self.camera = None
        self.results = []
    
    def log_result(self, test_name: str, success: bool, details: str):
        """Log a test result"""
        status = "✅ PASS" if success else "❌ FAIL"
        print(f"\n[{test_name}] {status}")
        print(f"   {details}")
        self.results.append({"test": test_name, "success": success, "details": details})
    
    async def run(self):
        """Run full diagnostic"""
        print("\n" + "=" * 70)
        print("  BLINK MINI LIVE VIEW DIAGNOSTIC")
        print("  " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        print("=" * 70)
        
        try:
            # 1. Load credentials
            print("\n📁 PHASE 1: Loading Credentials")
            print("-" * 50)
            
            if not os.path.exists(self.token_file):
                self.log_result("Load Token", False, f"File not found: {self.token_file}")
                print("\n💡 Run explore_cameras.py first to authenticate!")
                return
            
            with open(self.token_file, 'r') as f:
                self.auth_data = json.load(f)
            
            print(f"   Token: {self.auth_data.get('token', 'N/A')[:40]}...")
            print(f"   Account: {self.auth_data.get('account_id', 'N/A')}")
            print(f"   Region: {self.auth_data.get('region_id', 'N/A')}")
            self.log_result("Load Token", True, "Credentials loaded")
            
            # 2. Authenticate
            print("\n🔐 PHASE 2: Authenticating with Blink")
            print("-" * 50)
            
            from blinkpy.blinkpy import Blink
            from blinkpy.auth import Auth
            
            self.session = aiohttp.ClientSession()
            self.blink = Blink(session=self.session)
            self.blink.auth = Auth(self.auth_data, no_prompt=True)
            
            print("   Connecting...")
            await self.blink.start()
            print(f"   ✅ Connected! Found {len(self.blink.cameras)} camera(s)")
            self.log_result("Authentication", True, f"{len(self.blink.cameras)} cameras found")
            
            # 3. Find Mini camera
            print("\n📷 PHASE 3: Finding Camera")
            print("-" * 50)
            
            for name, cam in self.blink.cameras.items():
                cam_type = (cam.camera_type or cam.product_type or "unknown").lower()
                print(f"   - {name} (Type: {cam_type}, ID: {cam.camera_id})")
                
                if 'mini' in cam_type or 'owl' in cam_type:
                    self.camera = cam
            
            if not self.camera and self.blink.cameras:
                name, self.camera = list(self.blink.cameras.items())[0]
            
            if not self.camera:
                self.log_result("Find Camera", False, "No cameras available")
                return
            
            print(f"\n   Selected: {self.camera.name}")
            self.log_result("Find Camera", True, f"Using {self.camera.name}")
            
            # 4. Get liveview URL
            print("\n🔗 PHASE 4: Getting Liveview URL")
            print("-" * 50)
            
            try:
                url = await self.camera.get_liveview()
                print(f"   URL: {url}")
                
                is_immis = url.startswith("immis://")
                is_rtsp = url.startswith("rtsp")
                
                if is_immis:
                    print("   ⚠️ This is an IMMIS URL (proprietary protocol)")
                elif is_rtsp:
                    print("   ✅ This is a standard RTSP URL")
                
                self.log_result("Get Liveview URL", True, f"Protocol: {'IMMIS' if is_immis else 'RTSP'}")
                
            except Exception as e:
                self.log_result("Get Liveview URL", False, str(e))
                return
            
            # 5. Parse and test IMMIS connection
            if is_immis:
                await self._test_immis(url)
            
            # 6. Test blinkpy livestream proxy
            print("\n🔧 PHASE 6: Testing blinkpy Livestream Proxy")
            print("-" * 50)
            
            await self._test_blinkpy_proxy()
            
            # 7. Summary
            self._print_summary()
            
        except Exception as e:
            print(f"\n❌ DIAGNOSTIC ERROR: {e}")
            traceback.print_exc()
        
        finally:
            if self.session:
                await self.session.close()
    
    async def _test_immis(self, url: str):
        """Test IMMIS protocol connection"""
        print("\n🌐 PHASE 5: Testing IMMIS Connection")
        print("-" * 50)
        
        # Parse URL
        rest = url[8:]  # Remove "immis://"
        if '/' in rest:
            hostport, path = rest.split('/', 1)
            path = '/' + path
        else:
            hostport, path = rest, '/'
        
        if ':' in hostport:
            host, port = hostport.split(':')
            port = int(port)
        else:
            host, port = hostport, 443
        
        print(f"   Host: {host}")
        print(f"   Port: {port}")
        print(f"   Path: {path}")
        
        # Test DNS
        print(f"\n   [5.1] DNS Resolution...")
        try:
            ip = socket.gethostbyname(host)
            print(f"         ✅ {host} → {ip}")
        except Exception as e:
            print(f"         ❌ DNS failed: {e}")
            return
        
        # Test TCP + TLS
        print(f"\n   [5.2] TLS Connection...")
        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE
        
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(host, port, ssl=ssl_ctx),
                timeout=10.0
            )
            print(f"         ✅ TLS connected")
        except Exception as e:
            print(f"         ❌ Connection failed: {e}")
            self.log_result("IMMIS Connection", False, str(e))
            return
        
        # Test subscription
        print(f"\n   [5.3] Testing Subscriptions...")
        
        # Extract session from path
        session_id = path.strip('/').split('?')[0] if path else None
        
        payloads = [
            ("Simple", json.dumps({
                "type": "subscribe",
                "session": session_id,
                "camera_id": self.camera.camera_id,
                "network_id": self.camera.network_id
            })),
            ("With Auth", json.dumps({
                "type": "subscribe", 
                "session": session_id,
                "auth_token": self.auth_data.get("token"),
                "account_id": self.auth_data.get("account_id"),
                "camera_id": self.camera.camera_id,
                "network_id": self.camera.network_id
            })),
            ("Full", json.dumps({
                "action": "subscribe",
                "channel": f"liveview/{self.camera.network_id}/{self.camera.camera_id}",
                "auth_token": self.auth_data.get("token"),
                "account_id": self.auth_data.get("account_id"),
                "client_id": self.auth_data.get("client_id"),
                "network_id": self.camera.network_id,
                "camera_id": self.camera.camera_id,
                "type": "live"
            }))
        ]
        
        for name, payload in payloads:
            print(f"\n         Testing '{name}' format...")
            
            try:
                # Reconnect
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(host, port, ssl=ssl_ctx),
                    timeout=10.0
                )
                
                # Send
                writer.write(payload.encode())
                await writer.drain()
                
                # Read response
                try:
                    data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
                    
                    if data:
                        print(f"         ✅ Received {len(data)} bytes!")
                        print(f"         Hex: {data[:30].hex()}")
                        
                        # Check if video
                        if b'\x00\x00\x00\x01' in data[:20] or b'\x00\x00\x01' in data[:20]:
                            print(f"         🎉 VIDEO DATA DETECTED!")
                            self.log_result("IMMIS Subscription", True, f"Video data received with '{name}' format")
                            return
                        
                        # Check if error JSON
                        try:
                            resp = json.loads(data.decode())
                            print(f"         JSON: {resp}")
                        except:
                            pass
                    else:
                        print(f"         ❌ 0 bytes received")
                        
                except asyncio.TimeoutError:
                    print(f"         ❌ Timeout (no response)")
                
                writer.close()
                
            except Exception as e:
                print(f"         ❌ Error: {e}")
        
        self.log_result("IMMIS Subscription", False, "No valid video data received from any format")
    
    async def _test_blinkpy_proxy(self):
        """Test blinkpy's built-in livestream proxy"""
        try:
            print("   Initializing livestream...")
            livestream = await self.camera.init_livestream()
            
            print(f"   Starting proxy...")
            await livestream.start(host="127.0.0.1", port=0)
            
            print(f"   ✅ Proxy URL: {livestream.url}")
            print(f"   Proxy port: {livestream.port}")
            
            # Start feed
            print("   Starting data feed...")
            feed_task = asyncio.create_task(livestream.feed())
            
            # Wait
            print("   Waiting 5 seconds for data...")
            await asyncio.sleep(5)
            
            # Test proxy
            print("   Connecting to proxy...")
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection('127.0.0.1', livestream.port),
                    timeout=5.0
                )
                
                data = await asyncio.wait_for(reader.read(4096), timeout=5.0)
                
                if data:
                    print(f"   ✅ Proxy returned {len(data)} bytes!")
                    self.log_result("blinkpy Proxy", True, f"Received {len(data)} bytes")
                else:
                    print(f"   ❌ Proxy returned 0 bytes")
                    self.log_result("blinkpy Proxy", False, "0 bytes - IMMIS handshake failing")
                
                writer.close()
                
            except asyncio.TimeoutError:
                print("   ❌ Proxy read timeout")
                self.log_result("blinkpy Proxy", False, "Timeout - no data flowing")
            
            # Cleanup
            feed_task.cancel()
            livestream.stop()
            
        except Exception as e:
            print(f"   ❌ Error: {e}")
            self.log_result("blinkpy Proxy", False, str(e))
    
    def _print_summary(self):
        """Print diagnostic summary"""
        print("\n" + "=" * 70)
        print("  DIAGNOSTIC SUMMARY")
        print("=" * 70)
        
        passed = sum(1 for r in self.results if r["success"])
        failed = sum(1 for r in self.results if not r["success"])
        
        print(f"\n   Tests Passed: {passed}")
        print(f"   Tests Failed: {failed}")
        
        if failed > 0:
            print("\n   FAILED TESTS:")
            for r in self.results:
                if not r["success"]:
                    print(f"   - {r['test']}: {r['details']}")
        
        print("\n" + "-" * 70)
        print("  RECOMMENDATIONS")
        print("-" * 70)
        
        # Check for common issues
        proxy_failed = any(r["test"] == "blinkpy Proxy" and not r["success"] for r in self.results)
        immis_failed = any("IMMIS" in r["test"] and not r["success"] for r in self.results)
        
        if proxy_failed or immis_failed:
            print("""
   The IMMIS protocol handshake is failing. This is a KNOWN ISSUE with
   Blink Mini cameras. Possible causes:

   1. BLINKPY VERSION: Update blinkpy to the latest version:
      pip install --upgrade blinkpy

   2. BLINK PROTOCOL CHANGE: Blink may have changed their IMMIS protocol.
      Check: https://github.com/fronzbot/blinkpy/issues
      
   3. WORKAROUND - Use these alternatives instead of live streaming:
   
      a) RECORD-AND-PLAY METHOD (Most Reliable):
         - Camera records a clip on demand
         - You download and play it
         - ~15 second delay but works reliably
         
      b) RAPID SNAPSHOT MODE:
         - Takes snapshots every 1-2 seconds
         - Not true video but shows what's happening
         - Works with all camera types

   4. ALTERNATIVE SOLUTION:
      The official Blink app works because it uses their closed-source
      SDK. Third-party solutions rely on reverse-engineering which
      can break when Blink updates their servers.
""")
        else:
            print("\n   All tests passed! Live streaming should work.")
        
        print("=" * 70)


async def main():
    diag = BlinkDiagnostic()
    await diag.run()


if __name__ == "__main__":
    print("\n⚠️  Make sure you have:")
    print("   1. blink_token.json in the current directory")
    print("   2. blinkpy installed: pip install blinkpy aiohttp")
    print()
    
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n\nInterrupted!")
    except Exception as e:
        print(f"\n❌ Error: {e}")
        traceback.print_exc()
