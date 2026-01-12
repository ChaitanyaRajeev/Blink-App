#!/usr/bin/env python3
"""
Explore Blink Cameras - List cameras, download images and videos
Based on blinkpy documentation: https://github.com/fronzbot/blinkpy
"""

import asyncio
import os
import json
from getpass import getpass
from aiohttp import ClientSession
from datetime import datetime

print("\n" + "="*70)
print("  BLINK CAMERA EXPLORER")
print("  List cameras, download images and videos")
print("="*70)

# Check if blinkpy is installed
try:
    from blinkpy.blinkpy import Blink
    from blinkpy.auth import Auth, BlinkTwoFARequiredError, UnauthorizedError
    print("\nâœ… blinkpy library is installed (v0.25.0+)")
except ImportError:
    print("\nâŒ blinkpy library not found!")
    print("Run: pip3 install --upgrade blinkpy")
    exit(1)

# Create output directory for downloads
OUTPUT_DIR = "blink_downloads"
TOKEN_FILE = "blink_token.json"

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)
    print(f"ðŸ“ Created output directory: {OUTPUT_DIR}/")

async def explore_cameras():
    """Authenticate and explore Blink cameras"""
    
    # Use async context manager for proper cleanup
    async with ClientSession() as session:
        blink = Blink(session=session)
        
        print("\n" + "="*70)
        print("STEP 1: LOGIN")
        print("="*70)
        
        # Try to load saved token first
        token_loaded = False
        if os.path.exists(TOKEN_FILE):
            print("\nðŸ”‘ Found saved token, attempting to reuse...")
            try:
                with open(TOKEN_FILE, "r") as f:
                    saved_creds = json.load(f)
                auth = Auth(saved_creds, no_prompt=True)
                blink.auth = auth
                await blink.start()
                token_loaded = True
                print("âœ… Login successful using saved token!")
            except Exception as e:
                print(f"âš ï¸  Saved token invalid or expired: {e}")
                print("   Will request fresh credentials...")
                token_loaded = False
        
        if not token_loaded:
            # Get credentials from user
            email = input("\nðŸ“§ Enter your Blink email: ")
            password = getpass("ðŸ”’ Enter your Blink password: ")
            
            auth = Auth({
                "username": email,
                "password": password
            }, no_prompt=True)
            
            blink.auth = auth
            
            try:
                # Authenticate
                print("\nâ³ Authenticating...")
                
                try:
                    await blink.start()
                    print("âœ… Login successful!")
                except BlinkTwoFARequiredError:
                    print("\nðŸ“§ 2FA Required - Check your email for the PIN!")
                    otp = input("ðŸ”¢ Enter the 2FA PIN: ").strip()
                    if otp:
                        await blink.send_2fa_code(otp)
                        print("âœ… 2FA verified!")
                    else:
                        print("âŒ No PIN entered.")
                        return
                
                # Complete setup
                await blink.setup_post_verify()
                print("âœ… Authentication complete!")
                
                # Save token for future use
                await blink.save(TOKEN_FILE)
                print(f"ðŸ’¾ Token saved to {TOKEN_FILE} for future use!")
                
            except UnauthorizedError:
                print("\nâŒ Invalid credentials")
                return
            except Exception as e:
                print(f"\nâŒ Error during login: {type(e).__name__}: {e}")
                import traceback
                traceback.print_exc()
                return
        
        try:
            # Show account info
            print("\n" + "="*70)
            print("STEP 2: ACCOUNT INFO")
            print("="*70)
            print(f"\nðŸ‘¤ Account ID: {blink.account_id}")
            print(f"ðŸŒ Region: {blink.auth.region_id}")
            print(f"ðŸ“ API Host: {blink.auth.host}")
            
            # List Sync Modules
            print("\n" + "="*70)
            print("STEP 3: SYNC MODULES")
            print("="*70)
            
            if blink.sync:
                print(f"\nðŸ“¡ Found {len(blink.sync)} sync module(s):")
                for sync_name, sync_module in blink.sync.items():
                    print(f"\n  Sync Module: {sync_name}")
                    print(f"    â€¢ ID: {sync_module.sync_id}")
                    print(f"    â€¢ Armed: {sync_module.arm}")
                    print(f"    â€¢ Status: {sync_module.status}")
            else:
                print("\nNo sync modules found.")
            
            # List Cameras
            print("\n" + "="*70)
            print("STEP 4: CAMERAS")
            print("="*70)
            
            if blink.cameras:
                print(f"\nðŸ“¹ Found {len(blink.cameras)} camera(s):")
                
                camera_list = []
                for idx, (name, camera) in enumerate(blink.cameras.items(), 1):
                    camera_list.append((name, camera))
                    print(f"\n  [{idx}] {name}")
                    print(f"      â€¢ Camera ID: {camera.camera_id}")
                    print(f"      â€¢ Network ID: {camera.network_id}")
                    print(f"      â€¢ Type: {camera.camera_type}")
                    print(f"      â€¢ Armed: {camera.arm}")
                    
                    # Print all available attributes
                    print(f"      â€¢ Attributes:")
                    attrs = camera.attributes
                    for key, value in attrs.items():
                        if key not in ['name', 'camera_id', 'network_id']:
                            print(f"          - {key}: {value}")
            else:
                print("\nNo cameras found.")
                return
            
            # Refresh to get latest data
            print("\n" + "="*70)
            print("STEP 5: REFRESH DATA")
            print("="*70)
            print("\nâ³ Refreshing camera data (force=True)...")
            await blink.refresh(force=True)
            print("âœ… Data refreshed!")
            
            # Download options
            print("\n" + "="*70)
            print("STEP 6: DOWNLOAD OPTIONS")
            print("="*70)
            
            print("\nWhat would you like to do?")
            print("  [1] Download latest thumbnail from all cameras")
            print("  [2] Download videos from cloud (motion events)")
            print("  [3] Download videos from local storage (sync module USB)")
            print("  [4] Snap a new picture from a camera")
            print("  [5] Record a new video clip from a camera")
            print("  [6] ðŸ”´ LIVE VIEW - Watch camera in real-time")
            print("  [7] Download everything (thumbnails + cloud videos)")
            print("  [8] Skip downloads")
            
            choice = input("\nðŸ”¢ Enter choice (1-8): ").strip()
            
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            
            if choice == "1" or choice == "7":
                # Download thumbnails
                print("\nðŸ“· Downloading thumbnails...")
                for name, camera in blink.cameras.items():
                    safe_name = name.replace(" ", "_").replace("/", "_")
                    filename = f"{OUTPUT_DIR}/{safe_name}_thumbnail_{timestamp}.jpg"
                    try:
                        await camera.image_to_file(filename)
                        print(f"   âœ… Saved: {filename}")
                    except Exception as e:
                        print(f"   âŒ Failed {name}: {e}")
            
            if choice == "2" or choice == "7":
                # Download videos from cloud storage
                print("\nðŸŽ¥ Downloading videos from Blink cloud...")
                print("   (These are motion-triggered recordings stored in Blink's servers)")
                
                # Ask how far back to go
                since_input = input("   ðŸ“… Download since date (YYYY/MM/DD) or press Enter for last 7 days: ").strip()
                if since_input:
                    since_date = since_input
                else:
                    # Default to 7 days ago
                    from datetime import timedelta
                    week_ago = datetime.now() - timedelta(days=7)
                    since_date = week_ago.strftime("%Y/%m/%d")
                    print(f"   Using default: {since_date}")
                
                # Ask which camera or all
                print("\n   ðŸ“¹ Which camera?")
                print("      [0] All cameras")
                for idx, (name, _) in enumerate(blink.cameras.items(), 1):
                    print(f"      [{idx}] {name}")
                cam_choice = input("   ðŸ”¢ Choose: ").strip()
                
                if cam_choice == "0" or cam_choice == "":
                    selected_camera = "all"
                else:
                    try:
                        cam_idx = int(cam_choice) - 1
                        selected_camera = list(blink.cameras.keys())[cam_idx]
                    except:
                        selected_camera = "all"
                
                print(f"\n   ðŸ“¥ Downloading videos since {since_date}...")
                print(f"   ðŸ“¹ Camera: {selected_camera}")
                
                # Count files before download
                files_before = set()
                for root, dirs, files in os.walk(OUTPUT_DIR):
                    for f in files:
                        files_before.add(os.path.join(root, f))
                
                try:
                    # Download videos for selected camera(s)
                    if selected_camera == "all":
                        for cam_name in blink.cameras.keys():
                            cam_dir = os.path.join(OUTPUT_DIR, cam_name.replace(" ", "_"))
                            os.makedirs(cam_dir, exist_ok=True)
                            print(f"\n   ðŸ“¥ Downloading {cam_name}...")
                            await blink.download_videos(cam_dir, since=since_date, camera=cam_name, stop=10, delay=2)
                    else:
                        cam_dir = os.path.join(OUTPUT_DIR, selected_camera.replace(" ", "_"))
                        os.makedirs(cam_dir, exist_ok=True)
                        await blink.download_videos(cam_dir, since=since_date, camera=selected_camera, stop=10, delay=2)
                    
                    # Count files after download
                    files_after = set()
                    for root, dirs, files in os.walk(OUTPUT_DIR):
                        for f in files:
                            files_after.add(os.path.join(root, f))
                    
                    new_files = files_after - files_before
                    video_files = [f for f in new_files if f.endswith('.mp4')]
                    
                    if video_files:
                        print(f"\n   âœ… Downloaded {len(video_files)} video(s):")
                        total_size = 0
                        for vf in sorted(video_files)[:20]:  # Show first 20
                            size = os.path.getsize(vf)
                            total_size += size
                            # Show relative path
                            rel_path = os.path.relpath(vf, OUTPUT_DIR)
                            print(f"      â€¢ {rel_path} ({size:,} bytes)")
                        if len(video_files) > 20:
                            print(f"      ... and {len(video_files) - 20} more")
                        print(f"\n   ðŸ“Š Total: {len(video_files)} videos, {total_size:,} bytes")
                    else:
                        print("\n   âš ï¸  No new videos found in Blink cloud storage.")
                        print("   ðŸ’¡ Tip: Videos only exist if motion was detected.")
                        print("      Use option [5] to record a new clip manually!")
                except Exception as e:
                    print(f"\n   âš ï¸  Cloud download failed: {e}")
                    import traceback
                    traceback.print_exc()
                    print("   Note: Videos only exist if motion was detected and recorded.")
            
            if choice == "3":
                # Download videos from local storage (sync module USB)
                print("\nðŸ’¾ Downloading videos from sync module local storage...")
                print("   (These are stored on the USB drive in your sync module)")
                
                for sync_name, sync_module in blink.sync.items():
                    print(f"\n   Processing sync module: {sync_name}")
                    try:
                        # Request manifest from local storage
                        manifest = await sync_module.get_manifest()
                        if manifest and 'clips' in manifest:
                            clips = manifest.get('clips', [])
                            print(f"   ðŸ“¹ Found {len(clips)} clip(s) in local storage")
                            
                            for i, clip in enumerate(clips[:10]):  # Limit to 10 clips
                                clip_id = clip.get('id')
                                clip_name = clip.get('camera_name', 'unknown')
                                created = clip.get('created_at', 'unknown')
                                print(f"      [{i+1}] {clip_name} - {created}")
                            
                            if clips:
                                dl_choice = input("\n   Download all clips? (yes/no): ").strip().lower()
                                if dl_choice == 'yes':
                                    for clip in clips[:10]:
                                        try:
                                            clip_id = clip.get('id')
                                            clip_name = clip.get('camera_name', 'unknown').replace(" ", "_")
                                            filename = f"{OUTPUT_DIR}/local_{clip_name}_{clip_id}.mp4"
                                            await sync_module.download_clip(clip_id, filename)
                                            print(f"      âœ… Saved: {filename}")
                                        except Exception as clip_err:
                                            print(f"      âŒ Failed clip {clip_id}: {clip_err}")
                        else:
                            print(f"   âš ï¸  No local storage clips found or USB not connected")
                    except Exception as e:
                        print(f"   âš ï¸  Local storage access failed: {e}")
                        print("   Note: Requires USB drive connected to sync module")
            
            if choice == "4":
                # Snap a new picture
                print("\nðŸ“· Available cameras:")
                for idx, (name, camera) in enumerate(camera_list, 1):
                    print(f"   [{idx}] {name}")
                
                cam_choice = input("\nðŸ”¢ Enter camera number: ").strip()
                try:
                    cam_idx = int(cam_choice) - 1
                    if 0 <= cam_idx < len(camera_list):
                        cam_name, cam = camera_list[cam_idx]
                        print(f"\nâ³ Snapping picture from {cam_name}...")
                        await cam.snap_picture()
                        print("âœ… Picture snapped!")
                        
                        print("â³ Waiting for server to process...")
                        await asyncio.sleep(5)  # Wait for processing
                        await blink.refresh()
                        
                        safe_name = cam_name.replace(" ", "_").replace("/", "_")
                        filename = f"{OUTPUT_DIR}/{safe_name}_snap_{timestamp}.jpg"
                        await cam.image_to_file(filename)
                        print(f"âœ… Saved: {filename}")
                    else:
                        print("âŒ Invalid camera number")
                except ValueError:
                    print("âŒ Invalid input")
            
            if choice == "5":
                # Record a new video clip
                print("\nðŸŽ¬ Record a new video clip")
                print("   Available cameras:")
                for idx, (name, camera) in enumerate(camera_list, 1):
                    print(f"   [{idx}] {name}")
                
                cam_choice = input("\nðŸ”¢ Enter camera number: ").strip()
                try:
                    cam_idx = int(cam_choice) - 1
                    if 0 <= cam_idx < len(camera_list):
                        cam_name, cam = camera_list[cam_idx]
                        print(f"\nâ³ Recording video from {cam_name}...")
                        print("   (This will record a short clip)")
                        
                        # Request video recording
                        await cam.record()
                        print("âœ… Recording started!")
                        
                        print("â³ Waiting for recording to complete (10 seconds)...")
                        await asyncio.sleep(10)
                        
                        # Refresh to get the new clip
                        await blink.refresh(force=True)
                        
                        # Download the clip
                        if cam.clip:
                            safe_name = cam_name.replace(" ", "_").replace("/", "_")
                            filename = f"{OUTPUT_DIR}/{safe_name}_recording_{timestamp}.mp4"
                            await cam.video_to_file(filename)
                            print(f"âœ… Saved: {filename}")
                        else:
                            print("âš ï¸  Clip not immediately available. Try downloading cloud videos.")
                    else:
                        print("âŒ Invalid camera number")
                except ValueError:
                    print("âŒ Invalid input")
                except Exception as e:
                    print(f"âŒ Recording failed: {e}")
            
            if choice == "6":
                # Live View - Record and play approach (more reliable for battery cameras)
                print("\nðŸ”´ LIVE VIEW")
                print("   Note: Blink cameras are battery-powered and sleep between events.")
                print("   This records a fresh clip and plays it (most reliable method).")
                print("\n   Available cameras:")
                for idx, (name, camera) in enumerate(camera_list, 1):
                    print(f"   [{idx}] {name}")
                
                cam_choice = input("\nðŸ”¢ Enter camera number: ").strip()
                try:
                    cam_idx = int(cam_choice) - 1
                    if 0 <= cam_idx < len(camera_list):
                        cam_name, cam = camera_list[cam_idx]
                        
                        import subprocess
                        import shutil
                        
                        print(f"\nâ³ Waking up {cam_name} and recording clip...")
                        print("   (This takes ~15-20 seconds as camera wakes from sleep)")
                        
                        # Request a recording from the camera
                        await cam.record()
                        print("   ðŸ“¹ Recording started...")
                        
                        # Wait for recording to complete (longer wait)
                        for i in range(15):
                            await asyncio.sleep(1)
                            print(f"   Recording... {i+1}/15s", end='\r')
                        print()
                        
                        # Refresh and retry to get the clip URL
                        print("   ðŸ”„ Fetching clip from server...")
                        clip_found = False
                        for attempt in range(5):
                            await blink.refresh(force=True)
                            if cam.clip:
                                clip_found = True
                                break
                            print(f"   â³ Waiting for server... (attempt {attempt+1}/5)")
                            await asyncio.sleep(3)
                        
                        # Download the clip
                        safe_name = cam_name.replace(" ", "_").replace("/", "_")
                        output_file = f"{OUTPUT_DIR}/{safe_name}_live_{timestamp}.mp4"
                        
                        if clip_found and cam.clip:
                            await cam.video_to_file(output_file)
                            
                            if os.path.exists(output_file) and os.path.getsize(output_file) > 0:
                                size = os.path.getsize(output_file)
                                print(f"   âœ… Clip saved: {output_file} ({size:,} bytes)")
                                
                                # Ask if user wants to play it
                                play = input("\n   ðŸŽ¬ Play the clip now? (yes/no): ").strip().lower()
                                if play == 'yes':
                                    # Try VLC first
                                    vlc_path = shutil.which('vlc')
                                    if not vlc_path:
                                        if os.path.exists('/Applications/VLC.app/Contents/MacOS/VLC'):
                                            vlc_path = '/Applications/VLC.app/Contents/MacOS/VLC'
                                    
                                    if vlc_path:
                                        print("   ðŸš€ Opening in VLC...")
                                        subprocess.Popen(
                                            [vlc_path, output_file],
                                            stdout=subprocess.DEVNULL,
                                            stderr=subprocess.DEVNULL
                                        )
                                    else:
                                        # Try ffplay
                                        ffplay_path = shutil.which('ffplay')
                                        if ffplay_path:
                                            print("   ðŸš€ Opening in FFplay...")
                                            subprocess.Popen(
                                                [ffplay_path, '-autoexit', output_file],
                                                stdout=subprocess.DEVNULL,
                                                stderr=subprocess.DEVNULL
                                            )
                                        else:
                                            # macOS open command
                                            print("   ðŸš€ Opening with default player...")
                                            subprocess.Popen(['open', output_file])
                                
                                # Offer continuous mode
                                continuous = input("\n   ðŸ”„ Record another clip? (yes/no): ").strip().lower()
                                while continuous == 'yes':
                                    print(f"\n   â³ Recording new clip from {cam_name}...")
                                    await cam.record()
                                    
                                    for i in range(15):
                                        await asyncio.sleep(1)
                                        print(f"   Recording... {i+1}/15s", end='\r')
                                    print()
                                    
                                    # Retry fetching clip
                                    print("   ðŸ”„ Fetching clip...")
                                    for attempt in range(5):
                                        await blink.refresh(force=True)
                                        if cam.clip:
                                            break
                                        print(f"   â³ Waiting... ({attempt+1}/5)")
                                        await asyncio.sleep(3)
                                    
                                    new_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                                    new_file = f"{OUTPUT_DIR}/{safe_name}_live_{new_timestamp}.mp4"
                                    
                                    if cam.clip:
                                        await cam.video_to_file(new_file)
                                        if os.path.exists(new_file) and os.path.getsize(new_file) > 0:
                                            size = os.path.getsize(new_file)
                                            print(f"   âœ… Saved: {new_file} ({size:,} bytes)")
                                            
                                            # Auto-play
                                            if vlc_path:
                                                subprocess.Popen(
                                                    [vlc_path, new_file],
                                                    stdout=subprocess.DEVNULL,
                                                    stderr=subprocess.DEVNULL
                                                )
                                            else:
                                                subprocess.Popen(['open', new_file])
                                        else:
                                            print("   âš ï¸  Clip not saved properly")
                                    else:
                                        print("   âš ï¸  Clip not available yet")
                                    
                                    continuous = input("\n   ðŸ”„ Record another clip? (yes/no): ").strip().lower()
                            else:
                                print("   âš ï¸  Clip file is empty or not created")
                        else:
                            print("   âš ï¸  No clip URL available. Camera may still be processing.")
                            print("   ðŸ’¡ Try again in a few seconds, or check if camera is online.")
                    else:
                        print("âŒ Invalid camera number")
                except ValueError:
                    print("âŒ Invalid input")
                except Exception as e:
                    print(f"âŒ Live view failed: {e}")
                    import traceback
                    traceback.print_exc()
            
            # Show cache info
            print("\n" + "="*70)
            print("STEP 7: CACHE INFO")
            print("="*70)
            
            print("\nðŸ“¦ Camera cache data:")
            for name, camera in blink.cameras.items():
                print(f"\n  {name}:")
                if camera.image_from_cache:
                    print(f"    â€¢ Image cache: {len(camera.image_from_cache)} bytes")
                else:
                    print(f"    â€¢ Image cache: Empty")
                
                if camera.video_from_cache:
                    print(f"    â€¢ Video cache: {len(camera.video_from_cache)} bytes")
                else:
                    print(f"    â€¢ Video cache: Empty")
            
            # Summary
            print("\n" + "="*70)
            print("âœ… EXPLORATION COMPLETE!")
            print("="*70)
            
            print(f"\nðŸ“ Downloads saved to: {OUTPUT_DIR}/")
            
            # List downloaded files
            files = os.listdir(OUTPUT_DIR)
            if files:
                print(f"ðŸ“„ Files downloaded:")
                for f in sorted(files):
                    filepath = os.path.join(OUTPUT_DIR, f)
                    size = os.path.getsize(filepath)
                    print(f"   â€¢ {f} ({size:,} bytes)")
            
            print("\nðŸ’¡ What you learned:")
            print("   â€¢ How to list all cameras and their attributes")
            print("   â€¢ How to refresh camera data")
            print("   â€¢ How to download thumbnails and videos")
            print("   â€¢ How to snap new pictures remotely")
            print("   â€¢ How to access the image/video cache")
            
        except Exception as e:
            print(f"\nâŒ Error: {type(e).__name__}: {e}")
            import traceback
            traceback.print_exc()
        
        # Allow time for connections to close gracefully
        await asyncio.sleep(0.5)
        print("\nðŸ”’ Session closed.")

if __name__ == "__main__":
    print("\nâš ï¸  This script will access your Blink cameras.")
    confirm = input("Continue? (yes/no): ")
    if confirm.lower() == 'yes':
        import sys
        import logging
        
        # Suppress asyncio cleanup warnings/errors
        logging.getLogger("asyncio").setLevel(logging.CRITICAL)
        
        try:
            asyncio.run(explore_cameras())
        except Exception:
            pass  # Ignore cleanup errors
        finally:
            # Suppress any remaining cleanup messages
            sys.stderr = open(os.devnull, 'w')
    else:
        print("ðŸ‘‹ Exiting.")

