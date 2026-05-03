import SwiftUI

// The herbarium plate. SwiftUI is the source of truth for layout and
// typography — the FLUX-generated illustration drops into the centre
// slot, and all other text (title, binomial, family, plate number,
// date) is rendered live from the database. Used both inline in the
// detail view and rasterised by ImageRenderer for PNG export.
struct PlateFrameView: View {
    let entry: Entry
    var refreshToken: UUID = UUID()
    // When set, the illustration slot renders this image synchronously
    // instead of going through LocalImage's async loader. Required for
    // ImageRenderer-based PNG export, where the rasteriser doesn't wait
    // for `.task(id:)` to resolve.
    var preloadedIllustration: NSImage? = nil

    var body: some View {
        ZStack {
            DS.paper
            Rectangle().stroke(DS.hairline, lineWidth: 1)
            Rectangle().stroke(DS.hairlineSoft, lineWidth: 1).padding(14)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 40)
                    .padding(.top, 36)
                    .padding(.bottom, 24)

                illustrationSlot
                    .padding(.horizontal, 40)

                footer
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            }
            .padding(14)
        }
        .aspectRatio(0.707, contentMode: .fit) // A4 portrait
    }

    private var header: some View {
        VStack(spacing: 6) {
            MonoLabel(text: "PLATE \(plateNumber)", color: DS.muted)
                .padding(.bottom, 8)
            Text(entry.commonName.uppercased())
                .font(DS.serif(28, weight: .regular))
                .tracking(1.2)
                .foregroundColor(DS.ink)
                .multilineTextAlignment(.center)
            if !entry.scientificName.isEmpty {
                Text(entry.scientificName)
                    .font(DS.serif(15, italic: true))
                    .foregroundColor(DS.inkSoft)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var illustrationSlot: some View {
        Group {
            if let preloaded = preloadedIllustration {
                Image(nsImage: preloaded)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let illus = entry.illustrationFilename {
                let url = AppPaths.illustrations.appendingPathComponent(illus)
                if FileManager.default.fileExists(atPath: url.path) {
                    LocalImage(url: url, refreshToken: refreshToken) {
                        PlatePlaceholder(label: entry.commonName)
                    }
                } else {
                    PlatePlaceholder(label: entry.commonName)
                }
            } else {
                PlatePlaceholder(label: entry.commonName)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 220)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            if !entry.family.isEmpty {
                Text(entry.family)
                    .font(DS.serif(13, italic: true))
                    .foregroundColor(DS.mutedDeep)
            }
            Spacer()
            MonoLabel(text: footerDate.uppercased(), color: DS.muted)
        }
    }

    private var plateNumber: String {
        let suffix = String(entry.id.replacingOccurrences(of: "-", with: "").prefix(4)).uppercased()
        return "Nº \(suffix)"
    }

    private var footerDate: String {
        let iso = ISO8601DateFormatter()
        let date: Date? = (entry.capturedAt.flatMap { iso.date(from: $0) })
            ?? iso.date(from: entry.createdAt)
        guard let d = date else { return entry.createdAt }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}
