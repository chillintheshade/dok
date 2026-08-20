#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3,
      let requestedSize = arguments.count == 3 ? Int(arguments[2]) : 1024,
      requestedSize > 0 else {
    fputs("Usage: generate-dok-app-icon.swift <output.png> [pixel-size]\n", stderr)
    exit(2)
}

let pixelSize = requestedSize
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fputs("Unable to create bitmap context\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.setShouldAntialias(true)
context.cgContext.setAllowsAntialiasing(true)

let canvas = NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)
NSColor.black.setFill()
canvas.fill(using: .copy)

let center = NSPoint(x: canvas.midX, y: canvas.midY)
let scale = CGFloat(pixelSize) / 18
let orbitRadius = 6.2 * scale
let satelliteRadius = 1.4 * scale
let centerRadius = 2 * scale

NSColor.white.setFill()
for index in 0..<8 {
    let angle = CGFloat(index) * (.pi / 4) - (.pi / 2)
    let dotCenter = NSPoint(
        x: center.x + cos(angle) * orbitRadius,
        y: center.y + sin(angle) * orbitRadius
    )
    NSBezierPath(
        ovalIn: NSRect(
            x: dotCenter.x - satelliteRadius,
            y: dotCenter.y - satelliteRadius,
            width: satelliteRadius * 2,
            height: satelliteRadius * 2
        )
    ).fill()
}

NSBezierPath(
    ovalIn: NSRect(
        x: center.x - centerRadius,
        y: center.y - centerRadius,
        width: centerRadius * 2,
        height: centerRadius * 2
    )
).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
} catch {
    fputs("Unable to write PNG: \(error)\n", stderr)
    exit(1)
}
