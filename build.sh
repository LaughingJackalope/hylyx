#!/bin/bash
# Build Hylyx
set -e

cd "$(dirname "$0")"

# Load credentials
[[ -f .env ]] && source .env
[[ -f .env.local ]] && source .env.local

TEAM_ID="${TEAM_ID:-}"
APPLE_ID="${APPLE_ID:-}"
NOTARIZE_PASSWORD="${NOTARIZE_PASSWORD:-}"

# Colors
G='\033[0;32m'; D='\033[0;90m'; R='\033[0m'
info() { echo -e "${D}[i]${R} $1"; }
ok()   { echo -e "${G}[✓]${R} $1"; }

# ─────────────────────────────────────────────────────────────
# Step 0: Clean build directory
# ─────────────────────────────────────────────────────────────
rm -rf build 2>/dev/null || sudo rm -rf build

# ─────────────────────────────────────────────────────────────
# Step 1: Generate icon (if source exists)
# ─────────────────────────────────────────────────────────────
if [[ -f pkg/Resources/hylyx.png ]]; then
    info "Generating icon..."
    ICONSET="/tmp/Hylyx.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s pkg/Resources/hylyx.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    done
    # Rename to match iconutil expectations
    mv "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png" 2>/dev/null || true
    mv "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png" 2>/dev/null || true
    mv "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
    mv "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
    mv "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png" 2>/dev/null || true
    # Regenerate base sizes
    sips -z 16 16 pkg/Resources/hylyx.png --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32 pkg/Resources/hylyx.png --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 128 128 pkg/Resources/hylyx.png --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 pkg/Resources/hylyx.png --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 pkg/Resources/hylyx.png --out "$ICONSET/icon_512x512.png" >/dev/null
    iconutil -c icns "$ICONSET" -o pkg/Resources/hylyx.icns 2>/dev/null || true
    rm -rf "$ICONSET"
fi

# ─────────────────────────────────────────────────────────────
# Step 2: Compile Swift
# ─────────────────────────────────────────────────────────────
[[ -z "$CLOUD" ]] && { echo "Error: CLOUD not set in .env"; exit 1; }

info "Compiling..."
mkdir -p build
sed -i '' "s|{{CLOUD}}|$CLOUD|g" src/Support/Defaults.swift
swiftc -O -target arm64-apple-macosx13.0 $(find src -name '*.swift') -o build/hylyx

# ─────────────────────────────────────────────────────────────
# Step 3: Create .app bundle
# ─────────────────────────────────────────────────────────────
info "Creating Hylyx.app..."
rm -rf build/Hylyx.app
mkdir -p build/Hylyx.app/Contents/{MacOS,Resources,lib}

cp pkg/Info.plist build/Hylyx.app/Contents/
cp build/hylyx build/Hylyx.app/Contents/MacOS/
cp pkg/hylyx.provisionprofile build/Hylyx.app/Contents/embedded.provisionprofile
[[ -f pkg/Resources/hylyx.icns ]] && cp pkg/Resources/hylyx.icns build/Hylyx.app/Contents/Resources/

# Helper binaries
cp e2fs/bin/e2fsck-hy build/Hylyx.app/Contents/lib/fsck
cp e2fs/bin/mke2fs-hy build/Hylyx.app/Contents/lib/mkfs
cp e2fs/bin/resize2fs-hy build/Hylyx.app/Contents/lib/resize
cp e2fs/bin/debugfs-hy build/Hylyx.app/Contents/lib/debugfs
chmod +x build/Hylyx.app/Contents/MacOS/* build/Hylyx.app/Contents/lib/*

# ─────────────────────────────────────────────────────────────
# Step 4: Codesign
# ─────────────────────────────────────────────────────────────
if security find-identity -p codesigning -v | grep -q "$TEAM_ID"; then
    info "Codesigning..."
    # Sign helper binaries first
    for bin in build/Hylyx.app/Contents/lib/*; do
        codesign --force --timestamp --options runtime \
            --sign "Developer ID Application: Samespace Inc. ($TEAM_ID)" \
            "$bin"
    done
    # Sign the app bundle
    codesign --force --timestamp --options runtime \
        --entitlements pkg/entitlements.plist \
        --sign "Developer ID Application: Samespace Inc. ($TEAM_ID)" \
        build/Hylyx.app

    # ─────────────────────────────────────────────────────────
    # Step 5: Notarize
    # ─────────────────────────────────────────────────────────
    if [[ -n "$APPLE_ID" && -n "$NOTARIZE_PASSWORD" ]]; then
        info "Notarizing (this may take a minute)..."
        ditto -c -k --keepParent build/Hylyx.app build/Hylyx.zip
        xcrun notarytool submit build/Hylyx.zip \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$NOTARIZE_PASSWORD" \
            --wait
        xcrun stapler staple build/Hylyx.app
        rm build/Hylyx.zip
        # ─────────────────────────────────────────────────────────
        # Step 6: Create installer package
        # ─────────────────────────────────────────────────────────
        info "Creating installer package..."
        
        # Create package root
        PKG_ROOT=$(mktemp -d)
        mkdir -p "$PKG_ROOT/Applications"
        cp -R build/Hylyx.app "$PKG_ROOT/Applications/"
        
        # Ensure scripts are executable
        chmod +x pkg/postinstall
        
        # Build component package
        pkgbuild --root "$PKG_ROOT" \
            --component-plist pkg/component.plist \
            --identifier dev.ss.hylyx \
            --version 1.0 \
            --scripts pkg \
            --install-location / \
            build/Hylyx-component.pkg
        
        # Build distribution package
        productbuild --distribution pkg/Distribution.xml \
            --resources pkg \
            --package-path build \
            build/Hylyx-unsigned.pkg
        
        # Sign the package
        productsign --sign "Developer ID Installer: Samespace Inc. ($TEAM_ID)" \
            build/Hylyx-unsigned.pkg build/Hylyx.pkg
        
        # Cleanup intermediates
        rm -rf "$PKG_ROOT" build/Hylyx-component.pkg build/Hylyx-unsigned.pkg
        
        # Notarize the package
        xcrun notarytool submit build/Hylyx.pkg \
            --apple-id "$APPLE_ID" \
            --team-id "$TEAM_ID" \
            --password "$NOTARIZE_PASSWORD" \
            --wait
        xcrun stapler staple build/Hylyx.pkg
        
        ok "Build complete (signed + notarized)"
        echo "   App:     build/Hylyx.app"
        echo "   Package: build/Hylyx.pkg"
    else
        ok "Build complete (signed, not notarized)"
        echo "   Set APPLE_ID and NOTARIZE_PASSWORD in .env to notarize"
    fi
else
    ok "Build complete (unsigned)"
    echo "   No signing identity found for $TEAM_ID"
fi

# ─────────────────────────────────────────────────────────────
# Step 7: Prepare hylyx-web folder
# ─────────────────────────────────────────────────────────────
info "Preparing hylyx-web folder..."
WEBDIR="../hylyx-web/cloud"
tar -czf "$WEBDIR/hylyx.tar.gz" -C build Hylyx.app
sed "s|{{URL}}|$CLOUD|g" install.sh.template > "$WEBDIR/install.sh"
cp uninstall.sh.template "$WEBDIR/uninstall.sh"
ok "hylyx-web folder ready"
echo "   $WEBDIR/hylyx.tar.gz"
echo "   $WEBDIR/install.sh"
echo "   $WEBDIR/uninstall.sh"
