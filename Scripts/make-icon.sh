#!/bin/bash
# Generates a procedural IconPing.icns by drawing a green-ring "ping" glyph
# at all required sizes via /usr/bin/sips on a 1024x1024 PNG produced inline
# with a tiny Swift script (no Xcode needed — uses just CoreGraphics from CLT).
#
# Output: build/IconPing.icns
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
ICONSET="$BUILD/IconPing.iconset"
mkdir -p "$ICONSET"

SRC_PNG="$BUILD/icon-1024.png"

cat > "$BUILD/_drawIcon.swift" <<'SWIFT'
import Foundation
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let outPath = CommandLine.arguments[1]
let size = 1024
let scale: CGFloat = 1
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

let rect = CGRect(x: 0, y: 0, width: size, height: size)

// rounded-square background
let corner: CGFloat = CGFloat(size) * 0.22
let bgPath = CGPath(roundedRect: rect.insetBy(dx: 0, dy: 0), cornerWidth: corner, cornerHeight: corner, transform: nil)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
// dark gradient background
let bgColors = [
    CGColor(srgbRed: 0.08, green: 0.10, blue: 0.13, alpha: 1.0),
    CGColor(srgbRed: 0.02, green: 0.04, blue: 0.06, alpha: 1.0)
]
let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: 0, y: CGFloat(size)),
    end:   CGPoint(x: CGFloat(size), y: 0),
    options: []
)
ctx.restoreGState()

// concentric "ping" rings — green
let center = CGPoint(x: CGFloat(size)/2, y: CGFloat(size)/2)
let baseR: CGFloat = CGFloat(size) * 0.13

for (i, alpha) in [0.18, 0.30, 0.55].enumerated() {
    let r = baseR + CGFloat(i + 1) * CGFloat(size) * 0.10
    ctx.setStrokeColor(CGColor(srgbRed: 0.20, green: 0.85, blue: 0.40, alpha: CGFloat(alpha)))
    ctx.setLineWidth(CGFloat(size) * 0.022)
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
}

// filled center dot
ctx.setFillColor(CGColor(srgbRed: 0.20, green: 0.92, blue: 0.40, alpha: 1.0))
let dotR = baseR
ctx.fillEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR*2, height: dotR*2))

// glow highlight
let highlightColors = [
    CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.4),
    CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0)
]
let hgrad = CGGradient(colorsSpace: colorSpace, colors: highlightColors as CFArray, locations: [0.0, 1.0])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: center.x - dotR, y: center.y - dotR, width: dotR*2, height: dotR*2))
ctx.clip()
ctx.drawRadialGradient(hgrad,
    startCenter: CGPoint(x: center.x - dotR*0.4, y: center.y + dotR*0.4),
    startRadius: 0,
    endCenter:   CGPoint(x: center.x, y: center.y),
    endRadius:   dotR,
    options: []
)
ctx.restoreGState()

guard let cgImage = ctx.makeImage() else { exit(2) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(3) }
CGImageDestinationAddImage(dest, cgImage, nil)
if !CGImageDestinationFinalize(dest) { exit(4) }
SWIFT

swift "$BUILD/_drawIcon.swift" "$SRC_PNG"

# All required sizes for an .icns
declare -a SIZES=(16 32 64 128 256 512 1024)
for s in 16 32 128 256 512; do
    /usr/bin/sips -z $s $s "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}.png"   >/dev/null
    /usr/bin/sips -z $((s*2)) $((s*2)) "$SRC_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
/usr/bin/sips -z 1024 1024 "$SRC_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns -o "$BUILD/IconPing.icns" "$ICONSET"
rm -rf "$ICONSET" "$BUILD/_drawIcon.swift"
echo "Wrote $BUILD/IconPing.icns"
