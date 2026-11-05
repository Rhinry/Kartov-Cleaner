import SwiftUI
import KartovCore

/// The Kartov globe: a small planet whose look says how much junk the Mac carries.
///
/// `dirt` 0 is a clean blue-green world with white clouds and a blue halo.
/// `dirt` 1 is a brown, smog-covered world with dark stains and debris in orbit.
/// Everything is drawn in a Canvas from the current time, so it needs no @State
/// (on the macOS 27 SDK @State is a macro that only full Xcode can expand).
struct Globe: View {
    var dirt: Double
    /// Radians per second.
    var speed: Double = 0.25
    var size: CGFloat = 220
    /// 0…1: a burst of sparkles and a stronger halo (end of a clean).
    var shine: Double = 0
    /// 0…1: processor load / heat. The halo turns orange and pulses.
    var heat: Double = 0
    /// 0…1: memory pressure. Grey cloud cover thickens.
    var fog: Double = 0
    /// 0…1: disk used, drawn as a ring around the planet. Nil: no ring.
    var ring: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, canvasSize in
                GlobePainter(dirt: max(0, min(1, dirt)),
                             angle: reduceMotion ? 0.6 : t * speed,
                             time: reduceMotion ? 0 : t,
                             shine: max(0, min(1, shine)),
                             heat: max(0, min(1, heat)),
                             fog: max(0, min(1, fog)),
                             ring: ring.map { max(0, min(1, $0)) })
                    .paint(&ctx, size: canvasSize)
            }
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if dirt < 0.08 { parts.append(L("Temiz bir dünya")) }
        else if dirt < 0.4 { parts.append(L("Biraz kirlenmiş bir dünya")) }
        else { parts.append(L("Çok kirli bir dünya")) }
        if heat > 0.3 { parts.append(L("ısınmış")) }
        if fog > 0.3 { parts.append(L("bulutlu")) }
        if let ring { parts.append(L("disk %{0} dolu", Int(ring * 100))) }
        return parts.joined(separator: ", ")
    }
}

/// Converts the bytes waiting to be cleaned into how dirty the globe looks.
func dirtLevel(_ bytes: Int64) -> Double {
    let gb = Double(bytes) / 1_000_000_000
    if gb <= 0.1 { return 0 }
    // 1 GB ≈ 0.25, 3 GB ≈ 0.5, 5 GB ≈ 0.66, 10 GB and up: fully dirty.
    return min(1, pow(gb / 10, 0.6))
}

// MARK: - painting

private struct RGB {
    var r: Double, g: Double, b: Double
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
    func mix(_ o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
    func color(_ a: Double = 1) -> Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Fixed pseudo-random numbers so the planet looks the same every frame.
private enum Seeds {
    static func rand(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
    /// Continent anchors: (longitude, latitude, spread, pieces), radians.
    private static let anchors: [(Double, Double, Double, Int)] = [
        (-1.70, 0.75, 0.20, 9), (-1.45, 0.40, 0.16, 7), (-1.15, -0.25, 0.14, 8), (-1.05, -0.60, 0.10, 5),
        (0.25, 0.75, 0.12, 6), (0.35, 0.15, 0.16, 9), (0.45, -0.35, 0.13, 7),
        (1.35, 0.75, 0.22, 11), (1.85, 0.50, 0.17, 8), (1.55, 0.25, 0.10, 5), (2.15, 0.10, 0.07, 4),
        (2.50, -0.50, 0.12, 6)
    ]
    /// Continents: many small overlapping blobs around each anchor, so the coastlines look organic.
    static let land: [(Double, Double, Double)] = {
        var out: [(Double, Double, Double)] = []
        for (k, (lon, lat, spread, n)) in anchors.enumerated() {
            for j in 0..<n {
                let i = k * 20 + j
                out.append((lon + (Seeds.rand(i + 900) * 2 - 1) * spread * 1.4,
                            lat + (Seeds.rand(i + 950) * 2 - 1) * spread,
                            0.06 + Seeds.rand(i + 990) * 0.09))
            }
        }
        return out
    }()
    static let clouds: [(Double, Double, Double)] = (0..<26).map { i in
        ((Seeds.rand(i) * 2 - 1) * .pi, (Seeds.rand(i + 40) * 2 - 1) * 1.15, 0.10 + Seeds.rand(i + 80) * 0.14)
    }
    static let stains: [(Double, Double, Double)] = (0..<36).map { i in
        ((Seeds.rand(i + 200) * 2 - 1) * .pi, (Seeds.rand(i + 240) * 2 - 1) * 1.15, 0.08 + Seeds.rand(i + 280) * 0.14)
    }
    /// Debris in orbit: (phase, tilt, distance, size).
    static let debris: [(Double, Double, Double, Double)] = (0..<30).map { i in
        (Seeds.rand(i + 400) * 2 * .pi, (Seeds.rand(i + 440) - 0.5) * 0.9, 1.18 + Seeds.rand(i + 480) * 0.32, 2 + Seeds.rand(i + 520) * 3.5)
    }
}

private struct GlobePainter {
    let dirt: Double
    let angle: Double
    let time: Double
    let shine: Double
    var heat: Double = 0
    var fog: Double = 0
    var ring: Double? = nil

    // Clean and dirty palettes, mixed by `dirt`.
    private let oceanLightClean = RGB(0x4FA3FF), oceanDarkClean = RGB(0x0B2E6B)
    private let oceanLightDirty = RGB(0x7A6A52), oceanDarkDirty = RGB(0x221B14)
    private let landClean = RGB(0x3DD68C), landCleanDark = RGB(0x1E7A4F)
    private let landDirty = RGB(0x6B5A3E), landDirtyDark = RGB(0x3A2F22)
    private let haloClean = RGB(0x6FB8FF), haloDirty = RGB(0xB0503A)

    func paint(_ ctx: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let R = side / 3                                  // planet radius; the rest is room for halo and debris
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let disc = CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2)

        drawHalo(&ctx, c: c, R: R)
        drawDebris(&ctx, c: c, R: R, front: false)

        // Planet body, clipped to the disc.
        ctx.drawLayer { layer in
            layer.clip(to: Path(ellipseIn: disc))
            let tone = min(1, pow(dirt, 0.7) * 1.1)
            let light = oceanLightClean.mix(oceanLightDirty, tone)
            let dark = oceanDarkClean.mix(oceanDarkDirty, tone)
            layer.fill(Path(ellipseIn: disc), with: .radialGradient(
                Gradient(colors: [light.color(), dark.color()]),
                center: CGPoint(x: c.x - R * 0.35, y: c.y - R * 0.4), startRadius: 0, endRadius: R * 1.5))

            let land = landClean.mix(landDirty, tone).color()
            for (lon, lat, r) in Seeds.land { blob(&layer, c: c, R: R, lon: lon, lat: lat, r: r, fill: land, edge: nil) }
            // Lighter patches on some of the land, for relief.
            let relief = RGB(0x7FE8B0).mix(RGB(0x857155), dirt).color(0.5)
            for (i, (lon, lat, r)) in Seeds.land.enumerated() where i % 3 == 0 {
                blob(&layer, c: c, R: R, lon: lon - 0.03, lat: lat + 0.03, r: r * 0.5, fill: relief, edge: nil)
            }
            // Ice caps, drawn flat at the poles.
            let ice = RGB(0xEAF4FF).mix(RGB(0x9A8B74), dirt).color(0.85)
            layer.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.55, y: c.y - R * 1.06, width: R * 1.1, height: R * 0.26)), with: .color(ice))
            layer.fill(Path(ellipseIn: CGRect(x: c.x - R * 0.45, y: c.y + R * 0.84, width: R * 0.9, height: R * 0.22)), with: .color(ice))

            // Stains: pollution spots that appear as dirt grows.
            let stainCount = Int((Double(Seeds.stains.count) * min(1, dirt * 1.6)).rounded(.up))
            for (i, (lon, lat, r)) in Seeds.stains.prefix(stainCount).enumerated() {
                let oil = i % 3 == 0
                blob(&layer, c: c, R: R, lon: lon, lat: lat, r: r * (0.9 + 0.7 * dirt),
                     fill: oil ? Color(.sRGB, red: 0.06, green: 0.05, blue: 0.04, opacity: 0.75 + 0.2 * dirt)
                               : Color(.sRGB, red: 0.30, green: 0.22, blue: 0.12, opacity: 0.65 + 0.3 * dirt),
                     edge: oil ? Color(.sRGB, red: 0.55, green: 0.35, blue: 0.75) : nil)
            }

            // Clouds: white when clean, brown smog when dirty; they drift a little faster than the ground.
            let cloud = RGB(r: 1, g: 1, b: 1).mix(RGB(0x8C7A62), dirt)
            for (i, (lon, lat, r)) in Seeds.clouds.enumerated() {
                let drift = time * 0.05 * (1 + Double(i % 3) * 0.3)
                blob(&layer, c: c, R: R, lon: lon + drift, lat: lat, r: r * (1 + dirt * 0.5),
                     fill: cloud.color(0.22 + 0.35 * dirt), edge: nil, flat: 2.6)
            }

            // A brown smog veil over everything.
            if dirt > 0 {
                layer.fill(Path(ellipseIn: disc), with: .color(Color(.sRGB, red: 0.35, green: 0.26, blue: 0.16, opacity: 0.42 * dirt)))
            }

            // Memory pressure: a grey cover of extra cloud.
            if fog > 0 {
                for (i, (lon, lat, r)) in Seeds.clouds.enumerated() where i % 2 == 1 {
                    let drift = time * 0.03 * (1 + Double(i % 3) * 0.4)
                    blob(&layer, c: c, R: R, lon: lon - drift + 0.6, lat: lat * 0.8, r: r * (1.4 + fog),
                         fill: Color(.sRGB, red: 0.78, green: 0.80, blue: 0.84, opacity: 0.35 * fog), edge: nil, flat: 2.2)
                }
                layer.fill(Path(ellipseIn: disc), with: .color(Color(.sRGB, red: 0.62, green: 0.65, blue: 0.70, opacity: 0.18 * fog)))
            }

            // Day/night shading and a soft highlight.
            layer.fill(Path(ellipseIn: disc), with: .radialGradient(
                Gradient(colors: [.clear, .black.opacity(0.62)]),
                center: CGPoint(x: c.x - R * 0.45, y: c.y - R * 0.5), startRadius: R * 0.5, endRadius: R * 2.0))
            layer.fill(Path(ellipseIn: disc.insetBy(dx: R * 0.25, dy: R * 0.25).offsetBy(dx: -R * 0.35, dy: -R * 0.4)),
                       with: .radialGradient(Gradient(colors: [.white.opacity(0.22 * (1 - dirt * 0.7)), .clear]),
                                             center: CGPoint(x: c.x - R * 0.4, y: c.y - R * 0.45),
                                             startRadius: 0, endRadius: R * 0.55))
        }

        // Rim light.
        ctx.stroke(Path(ellipseIn: disc.insetBy(dx: 0.5, dy: 0.5)),
                   with: .color(haloClean.mix(haloDirty, dirt).mix(RGB(0xFF8A3D), heat).color(0.45 + 0.3 * shine + 0.3 * heat)),
                   lineWidth: 1.2 + CGFloat(heat))

        if let ring { drawRing(&ctx, c: c, R: R, fraction: ring) }

        drawDebris(&ctx, c: c, R: R, front: true)
        if shine > 0 { drawSparkles(&ctx, c: c, R: R) }
    }

    /// A round patch on the sphere, drawn with horizontal foreshortening toward the edge.
    private func blob(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat,
                      lon: Double, lat: Double, r: Double, fill: Color, edge: Color?, flat: Double = 1) {
        let l = lon + angle
        let z = cos(lat) * cos(l)
        guard z > -0.15 else { return }
        let x = cos(lat) * sin(l)
        let y = sin(lat)
        let w = CGFloat(r) * R * 2 * CGFloat(max(0.18, z)) * CGFloat(max(1, flat))
        let h = CGFloat(r) * R * 2 * CGFloat(max(0.25, cos(lat) * 0.6 + 0.4)) / CGFloat(flat > 1 ? flat * 0.9 : 1)
        let p = CGPoint(x: c.x + CGFloat(x) * R, y: c.y - CGFloat(y) * R)
        let rect = CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
        let fade = min(1, max(0, (z + 0.15) / 0.35))
        var g = ctx
        g.opacity = fade
        g.fill(Path(ellipseIn: rect), with: .color(fill))
        if let edge { g.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)), with: .color(edge.opacity(0.35)), lineWidth: 1) }
    }

    private func drawHalo(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        let pulse = heat > 0 ? 0.85 + 0.15 * sin(time * (2 + heat * 3)) : 1
        let halo = haloClean.mix(haloDirty, dirt).mix(RGB(0xFF8A3D), heat * 0.85)
        let strength = (0.32 + 0.18 * (1 - dirt) + 0.2 * dirt + 0.35 * shine + 0.25 * heat) * pulse
        let outer = R * (1.38 + 0.12 * CGFloat(shine))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: halo.color(strength), location: 0.70),
                    .init(color: halo.color(0), location: 1.0)]),
                    center: c, startRadius: 0, endRadius: outer))
    }

    /// Disk use as a thin ring: blue when there is room, yellow when tight, red when nearly full.
    private func drawRing(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, fraction: Double) {
        let r = R * 1.30
        let w = max(2, R * 0.035)
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.08)), lineWidth: w)
        var arc = Path()
        arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
        let color: RGB = fraction >= 0.9 ? RGB(0xFF5A5F) : (fraction >= 0.8 ? RGB(0xF2D16B) : RGB(0x6FB8FF))
        ctx.stroke(arc, with: .color(color.color(0.9)), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }

    private func drawDebris(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat, front: Bool) {
        let count = Int((Double(Seeds.debris.count) * min(1, dirt * 1.5)).rounded(.up))
        guard count > 0 else { return }
        for (i, (phase, tilt, dist, sz)) in Seeds.debris.prefix(count).enumerated() {
            let a = phase + time * (0.35 + Double(i % 4) * 0.08)
            let z = sin(a)
            if (z >= 0) != front { continue }
            let x = cos(a) * dist
            let y = sin(a) * tilt * dist
            let p = CGPoint(x: c.x + CGFloat(x) * R, y: c.y + CGFloat(y) * R)
            let s = R * CGFloat(0.025 + sz * 0.012) * (front ? 1.15 : 0.8)
            var g = ctx
            g.opacity = front ? 0.95 : 0.5
            g.translateBy(x: p.x, y: p.y)
            g.rotate(by: .radians(a * 2 + Double(i)))
            let shape = i % 3 == 0 ? Path(ellipseIn: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                                   : Path(roundedRect: CGRect(x: -s / 2, y: -s / 2, width: s, height: s * 0.7), cornerRadius: 1)
            g.fill(shape, with: .color(i % 2 == 0 ? Color(.sRGB, red: 0.55, green: 0.48, blue: 0.40) : Color(.sRGB, red: 0.38, green: 0.33, blue: 0.28)))
        }
    }

    private func drawSparkles(_ ctx: inout GraphicsContext, c: CGPoint, R: CGFloat) {
        for i in 0..<10 {
            let a = Seeds.rand(i + 600) * 2 * .pi
            let d = R * CGFloat(1.15 + Seeds.rand(i + 640) * 0.35 + shine * 0.15)
            let twinkle = 0.5 + 0.5 * sin(time * 5 + Double(i))
            let s = CGFloat(3 + Seeds.rand(i + 680) * 5) * CGFloat(shine) * CGFloat(0.6 + 0.4 * twinkle)
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * d, y: c.y + CGFloat(sin(a)) * d)
            var star = Path()
            star.move(to: CGPoint(x: p.x, y: p.y - s)); star.addLine(to: CGPoint(x: p.x + s * 0.25, y: p.y - s * 0.25))
            star.addLine(to: CGPoint(x: p.x + s, y: p.y)); star.addLine(to: CGPoint(x: p.x + s * 0.25, y: p.y + s * 0.25))
            star.addLine(to: CGPoint(x: p.x, y: p.y + s)); star.addLine(to: CGPoint(x: p.x - s * 0.25, y: p.y + s * 0.25))
            star.addLine(to: CGPoint(x: p.x - s, y: p.y)); star.addLine(to: CGPoint(x: p.x - s * 0.25, y: p.y - s * 0.25))
            star.closeSubpath()
            ctx.fill(star, with: .color(.white.opacity(0.85 * shine)))
        }
    }
}
