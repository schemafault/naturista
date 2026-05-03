import SwiftUI

struct EntryRowView: View {
    let entry: Entry
    var width: CGFloat = 240

    @State private var hovered = false

    private var aspectRatio: CGFloat { PlateRatio.ratio(for: entry.id) }
    private var height: CGFloat { width / aspectRatio }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                figure
                    .frame(width: width, height: height)
                    .background(DS.paper)
                    .overlay(
                        Rectangle()
                            .stroke(hovered ? DS.inkSoft : DS.hairlineSoft, lineWidth: 1)
                    )

                MonoLabel(text: indexLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.commonName)
                    .font(DS.serif(17, weight: .regular))
                    .foregroundColor(DS.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.scientificName.isEmpty {
                    Text(entry.scientificName)
                        .font(DS.serif(13, italic: true))
                        .foregroundColor(DS.mutedDeep)
                        .lineLimit(1)
                }
            }
            .padding(.top, 10)
            .opacity(hovered ? 1 : 0)
            .offset(y: hovered ? 0 : -2)
            .animation(.easeOut(duration: 0.22), value: hovered)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var figure: some View {
        if let plate = entry.plateFilename {
            let url = AppPaths.plates.appendingPathComponent(plate)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalImage(url: url, fallback: { illustrationOrPlaceholder })
            } else {
                illustrationOrPlaceholder
            }
        } else {
            illustrationOrPlaceholder
        }
    }

    @ViewBuilder
    private var illustrationOrPlaceholder: some View {
        if let illus = entry.illustrationFilename {
            let url = AppPaths.illustrations.appendingPathComponent(illus)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalImage(url: url, fallback: { workingOrPlaceholder })
            } else {
                workingOrPlaceholder
            }
        } else {
            workingOrPlaceholder
        }
    }

    @ViewBuilder
    private var workingOrPlaceholder: some View {
        let workingURL = AppPaths.working.appendingPathComponent(entry.workingImageFilename)
        if FileManager.default.fileExists(atPath: workingURL.path) {
            LocalImage(url: workingURL, fallback: { PlatePlaceholder(label: entry.commonName) })
        } else {
            PlatePlaceholder(label: entry.commonName)
        }
    }

    private var indexLabel: String {
        let suffix = String(entry.id.replacingOccurrences(of: "-", with: "").prefix(4)).uppercased()
        return "Nº \(suffix)"
    }
}

// Loads a local image off the main thread and fades into a fallback view if
// the load fails. Avoids AsyncImage's URLCache which lingers on regenerated
// plate files.
struct LocalImage<Fallback: View>: View {
    let url: URL
    var contentMode: ContentMode = .fit
    @ViewBuilder var fallback: () -> Fallback

    @State private var image: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipped()
            } else if didLoad {
                fallback()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            image = nil
            didLoad = false
            let target = url
            let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
                guard let data = try? Data(contentsOf: target) else { return nil }
                return NSImage(data: data)
            }.value
            if Task.isCancelled { return }
            image = loaded
            didLoad = true
        }
    }
}

extension Entry {
    var commonName: String {
        guard let data = self.identificationJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topCandidate = json["top_candidate"] as? [String: Any],
              let name = topCandidate["common_name"] as? String else {
            return "Unidentified"
        }
        return name
    }

    var scientificName: String {
        guard let data = self.identificationJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topCandidate = json["top_candidate"] as? [String: Any],
              let name = topCandidate["scientific_name"] as? String else {
            return ""
        }
        return name
    }

    var family: String {
        guard let data = self.identificationJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let topCandidate = json["top_candidate"] as? [String: Any],
              let fam = topCandidate["family"] as? String else {
            return ""
        }
        return fam
    }
}
