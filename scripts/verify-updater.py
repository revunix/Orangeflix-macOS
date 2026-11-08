#!/usr/bin/env python3
"""Check the Sparkle sandbox configuration of a built application."""

import plistlib
import subprocess
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 scripts/verify-updater.py /path/to/Orangeflix.app")

    app = Path(sys.argv[1])
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)

    entitlements = plistlib.loads(
        subprocess.run(
            ["codesign", "-d", "--entitlements", ":-", str(app)],
            check=True,
            capture_output=True,
        ).stdout
    )
    bundle_id = info["CFBundleIdentifier"]
    allowed_services = set(
        entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name", [])
    )
    required_services = {f"{bundle_id}-spks", f"{bundle_id}-spki"}
    installer = app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"

    checks = {
        "App Sandbox": entitlements.get("com.apple.security.app-sandbox") is True,
        "outgoing network access": entitlements.get("com.apple.security.network.client") is True,
        "Sparkle installer service enabled": info.get("SUEnableInstallerLauncherService") is True,
        "Sparkle installer service embedded": installer.is_dir(),
        "Sparkle installer communication": required_services <= allowed_services,
        "Sparkle update public key": bool(info.get("SUPublicEDKey")),
        "Sparkle feed URL": bool(info.get("SUFeedURL")),
    }
    for name, ok in checks.items():
        print(f"{'OK' if ok else 'FAIL'}: {name}")
    if not all(checks.values()):
        raise SystemExit("Sparkle configuration verification failed")


if __name__ == "__main__":
    main()
