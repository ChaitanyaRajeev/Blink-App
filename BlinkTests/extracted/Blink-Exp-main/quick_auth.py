#!/usr/bin/env python3
"""
Quick Blink Authentication - Creates blink_token.json
"""

import asyncio
from aiohttp import ClientSession
from blinkpy.blinkpy import Blink
from blinkpy.auth import Auth

TOKEN_FILE = "blink_token.json"

async def authenticate():
    session = ClientSession()
    try:
        blink = Blink(session=session)
        
        print("\n" + "="*50)
        print("  BLINK QUICK AUTHENTICATION")
        print("="*50)
        
        # Get credentials from user
        email = input("\n📧 Enter your Blink email: ").strip()
        password = input("🔑 Enter your Blink password: ")
        
        print(f"\n📧 Using email: {email}")
        
        auth = Auth({"username": email, "password": password}, no_prompt=True)
        blink.auth = auth
        
        print("⏳ Authenticating...")
        
        try:
            await blink.start()
            print("✅ Logged in!")
        except Exception as e:
            print(f"\n📧 2FA Required - Check your email for the PIN!")
            otp = input("📢 Enter the 2FA PIN: ").strip()
            
            if otp:
                try:
                    await blink.send_2fa_code(otp)
                    await blink.setup_post_verify()
                    print("✅ 2FA verified!")
                except Exception as e2:
                    print(f"❌ 2FA Error: {e2}")
                    return False
            else:
                print("❌ No PIN entered")
                return False
        
        # Save token
        await blink.save(TOKEN_FILE)
        print(f"\n💾 Token saved to {TOKEN_FILE}")
        
        # Show cameras
        print(f"\n📹 Found {len(blink.cameras)} camera(s):")
        for name, cam in blink.cameras.items():
            print(f"   • {name} (ID: {cam.camera_id})")
        
        print("\n✅ You can now run: python3 working_solution.py")
        return True
        
    finally:
        await session.close()

if __name__ == "__main__":
    try:
        asyncio.run(authenticate())
    except KeyboardInterrupt:
        print("\n👋 Cancelled")
    except Exception as e:
        print(f"❌ Error: {e}")
