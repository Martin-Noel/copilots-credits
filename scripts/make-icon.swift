// Generates Resources/AppIcon.icns: a credit gauge on a macOS-style tile.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit
import SwiftUI

/// 1024×1024 canvas following Apple's macOS icon grid (824 pt tile, 100 pt margin).
struct AppIcon: View {
    /// Start and sweep of the gauge, in degrees (0° = 3 o'clock, clockwise).
    let start = 135.0, sweep = 270.0, filled = 0.62

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.27, blue: 0.62),
                                              Color(red: 0.07, green: 0.09, blue: 0.24)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 4))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 20, y: 12)

            // Track
            Arc(start: start, sweep: sweep)
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .frame(width: 520, height: 520)

            // Used credits: green → amber → orange
            Arc(start: start, sweep: sweep * filled)
                .stroke(AngularGradient(colors: [Color(red: 0.25, green: 0.85, blue: 0.55),
                                                 Color(red: 0.98, green: 0.80, blue: 0.25),
                                                 Color(red: 1.00, green: 0.50, blue: 0.25)],
                                        center: .center,
                                        startAngle: .degrees(start), endAngle: .degrees(start + sweep)),
                        style: StrokeStyle(lineWidth: 64, lineCap: .round))
                .frame(width: 520, height: 520)

            // Needle + hub
            Capsule()
                .fill(.white)
                .frame(width: 210, height: 26)
                .offset(x: 105)
                .rotationEffect(.degrees(start + sweep * filled))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            Circle().fill(.white).frame(width: 74, height: 74)
            Circle().fill(Color(red: 0.13, green: 0.17, blue: 0.42)).frame(width: 30, height: 30)

            // "AI" sparkle
            Sparkle()
                .fill(.white)
                .frame(width: 120, height: 120)
                .offset(x: 268, y: -268)
                .shadow(color: .white.opacity(0.5), radius: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct Arc: Shape {
    let start: Double, sweep: Double
    func path(in r: CGRect) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: r.width / 2,
                     startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
        }
    }
}

/// Four-pointed star with concave sides.
struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), s = r.width / 2
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        for (x, y) in [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)] {
            p.addQuadCurve(to: CGPoint(x: c.x + x * s, y: c.y + y * s), control: c)
        }
        return p
    }
}

@MainActor func render() throws {
    let iconset = URL(fileURLWithPath: "build/AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let renderer = ImageRenderer(content: AppIcon())
    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            renderer.scale = CGFloat(size * scale) / 1024
            guard let cg = renderer.cgImage else { fatalError("render failed") }
            let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
            try png.write(to: iconset.appendingPathComponent(name))
        }
    }

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
    try task.run()
    task.waitUntilExit()
    print(task.terminationStatus == 0 ? "✓ Resources/AppIcon.icns" : "iconutil failed")
}

try MainActor.assumeIsolated { try render() }
