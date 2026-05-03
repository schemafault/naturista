import SwiftUI

// Warm-paper herbarium design tokens. sRGB approximations of the
// design's oklch values.
enum DS {
    static let paper        = Color(red: 245/255, green: 240/255, blue: 229/255)
    static let paperDeep    = Color(red: 238/255, green: 232/255, blue: 218/255)
    static let paperEdge    = Color(red: 229/255, green: 222/255, blue: 205/255)
    static let ink          = Color(red:  42/255, green:  36/255, blue:  29/255)
    static let inkSoft      = Color(red:  79/255, green:  70/255, blue:  57/255)
    static let muted        = Color(red: 128/255, green: 120/255, blue: 101/255)
    static let mutedDeep    = Color(red: 107/255, green: 100/255, blue:  82/255)
    static let hairline     = Color(red: 201/255, green: 192/255, blue: 171/255)
    static let hairlineSoft = Color(red: 217/255, green: 210/255, blue: 190/255)
    static let sage         = Color(red: 111/255, green: 129/255, blue: 102/255)
    static let amber        = Color(red: 178/255, green: 152/255, blue:  92/255)
    static let rust         = Color(red: 159/255, green: 109/255, blue:  72/255)

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular, italic: Bool = false) -> Font {
        let f = Font.system(size: size, weight: weight, design: .serif)
        return italic ? f.italic() : f
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .monospaced)
    }
}

// Small uppercase tracking-heavy label used for section eyebrows.
struct Eyebrow: View {
    let text: String
    var size: CGFloat = 10.5
    var color: Color = DS.mutedDeep
    var body: some View {
        Text(text.uppercased())
            .font(DS.sans(size, weight: .medium))
            .tracking(size * 0.18)
            .foregroundColor(color)
    }
}

// Monospace meta label, e.g. "PLATE Nº 003".
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 10.5
    var color: Color = DS.muted
    var body: some View {
        Text(text)
            .font(DS.mono(size, weight: .regular))
            .tracking(size * 0.06)
            .foregroundColor(color)
    }
}

// 1-pixel hairline divider.
struct Hairline: View {
    var color: Color = DS.hairlineSoft
    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// Small confidence dot in sage / amber / rust.
struct ConfidenceDot: View {
    let level: String?
    var body: some View {
        let color: Color = {
            switch level?.lowercased() {
            case "high": return DS.sage
            case "medium", "med": return DS.amber
            case "low": return DS.rust
            default: return DS.muted
            }
        }()
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

// Small chip used in tag lists.
struct TagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.sans(10.5))
            .tracking(0.4)
            .foregroundColor(DS.inkSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairlineSoft, lineWidth: 1))
    }
}

// Minimal "Naturista" wordmark with a leaf glyph.
struct WordmarkLogo: View {
    var size: CGFloat = 18
    var body: some View {
        HStack(spacing: 8) {
            LeafGlyph(size: size)
                .foregroundColor(DS.ink)
            Text("Naturista")
                .font(DS.serif(16, weight: .medium))
                .tracking(0.32)
                .foregroundColor(DS.ink)
        }
    }
}

private struct LeafGlyph: View {
    var size: CGFloat
    var body: some View {
        Canvas { ctx, sz in
            var leaf = Path()
            let w = sz.width, h = sz.height
            leaf.move(to: CGPoint(x: w * 0.5, y: h * 0.06))
            leaf.addCurve(
                to: CGPoint(x: w * 0.5, y: h * 0.94),
                control1: CGPoint(x: w * 0.05, y: h * 0.30),
                control2: CGPoint(x: w * 0.05, y: h * 0.65)
            )
            leaf.addCurve(
                to: CGPoint(x: w * 0.5, y: h * 0.06),
                control1: CGPoint(x: w * 0.95, y: h * 0.65),
                control2: CGPoint(x: w * 0.95, y: h * 0.30)
            )
            ctx.stroke(leaf, with: .foreground, lineWidth: 0.9)

            var midrib = Path()
            midrib.move(to: CGPoint(x: w * 0.5, y: h * 0.18))
            midrib.addLine(to: CGPoint(x: w * 0.5, y: h * 0.86))
            ctx.stroke(midrib, with: .foreground, lineWidth: 0.7)
        }
        .frame(width: size, height: size)
    }
}

// 8-degree striped paper used for plate placeholders, with a centered
// uppercase label tag.
struct PlatePlaceholder: View {
    let label: String
    var labelMaxWidth: CGFloat? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DS.paperDeep
                StripePattern(spacing: 12, lineColor: DS.paperEdge, angle: 8)
                RadialGradient(
                    gradient: Gradient(colors: [Color.clear, DS.paperEdge.opacity(0.55)]),
                    center: .center,
                    startRadius: min(geo.size.width, geo.size.height) * 0.28,
                    endRadius: max(geo.size.width, geo.size.height) * 0.72
                )
                Text(label.uppercased())
                    .font(DS.mono(9.5, weight: .regular))
                    .tracking(1.7)
                    .foregroundColor(DS.mutedDeep)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: labelMaxWidth ?? min(geo.size.width * 0.7, 220))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.paper)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }
}

private struct StripePattern: View {
    let spacing: CGFloat
    let lineColor: Color
    let angle: Double

    var body: some View {
        GeometryReader { geo in
            let oversize = max(geo.size.width, geo.size.height) * 1.6
            Canvas { ctx, sz in
                var path = Path()
                var x: CGFloat = -oversize
                while x < oversize * 2 {
                    path.move(to: CGPoint(x: x, y: -oversize))
                    path.addLine(to: CGPoint(x: x, y: oversize * 2))
                    x += spacing
                }
                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
            }
            .frame(width: oversize * 2, height: oversize * 2)
            .rotationEffect(.degrees(angle))
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
}

// Quiet button — hairline border, no fill, ink text.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.sans(12, weight: .medium))
            .tracking(0.24)
            .foregroundColor(DS.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? DS.paperDeep : Color.clear)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

// Solid ink primary — used for the "Import photo" CTA.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.sans(12, weight: .medium))
            .tracking(0.24)
            .foregroundColor(DS.paper)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(configuration.isPressed ? DS.inkSoft : DS.ink)
            .contentShape(Rectangle())
    }
}

// Borderless ghost link — for back-navigation, alt actions.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.sans(12, weight: .medium))
            .tracking(0.24)
            .foregroundColor(configuration.isPressed ? DS.ink : DS.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? DS.paperDeep : Color.clear)
            .contentShape(Rectangle())
    }
}

