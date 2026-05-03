import SwiftUI

struct EntryRowView: View {
    let entry: Entry
    var aspectRatio: CGFloat = 1.0

    @State private var hovered = false

    var body: some View {
        let id = entry.identification
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(DS.paperDeep)
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        figure
                    }
                    .clipped()
                    .overlay(
                        Rectangle()
                            .stroke(hovered ? DS.inkSoft : DS.hairlineSoft, lineWidth: 1)
                    )

                HStack(spacing: 10) {
                    MonoLabel(text: indexLabel)
                    Rectangle()
                        .fill(DS.hairline)
                        .frame(width: 1, height: 9)
                    MonoLabel(text: id.kingdom.displayLabel, color: DS.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(id.commonName ?? "Unidentified")
                    .font(DS.serif(17, weight: .regular))
                    .foregroundColor(DS.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let scientific = id.scientificName, !scientific.isEmpty {
                    Text(scientific)
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
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    // The plate composition is rendered live by SwiftUI in the detail
    // view, so the gallery card just shows the raw illustration cropped
    // to fill its 4:5 tile. Falls back to the working photograph (and
    // finally a striped placeholder) while FLUX is still running.
    @ViewBuilder
    private var figure: some View {
        if let illus = entry.illustrationFilename {
            let url = AppPaths.illustrations.appendingPathComponent(illus)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalImage(url: url, contentMode: .fill, fallback: { workingOrPlaceholder })
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
        let label = entry.identification.commonName ?? "Unidentified"
        if FileManager.default.fileExists(atPath: workingURL.path) {
            LocalImage(url: workingURL, contentMode: .fill, fallback: { PlatePlaceholder(label: label) })
        } else {
            PlatePlaceholder(label: label)
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
    var refreshToken: UUID = UUID()
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
        .task(id: TaskKey(url: url, token: refreshToken)) {
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

    private struct TaskKey: Hashable {
        let url: URL
        let token: UUID
    }
}

