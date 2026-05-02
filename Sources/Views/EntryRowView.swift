import SwiftUI

struct EntryRowView: View {
    let entry: Entry
    let onRetry: ((Entry) -> Void)?
    let imageSize: CGFloat

    init(entry: Entry, imageSize: CGFloat = 160, onRetry: ((Entry) -> Void)? = nil) {
        self.entry = entry
        self.imageSize = imageSize
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                thumbnailImage
                    .frame(width: imageSize, height: imageSize)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )

                if entry.userStatus == "failed" {
                    errorBadge
                        .offset(x: -4, y: 4)
                } else if entry.modelConfidence == "low" {
                    warningBadge
                        .offset(x: -4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.commonName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(entry.scientificName)
                    .font(.caption2)
                    .italic()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if entry.userStatus == "failed", let onRetry = onRetry {
                Button("Retry") {
                    onRetry(entry)
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .frame(width: imageSize)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let illustrationFilename = entry.illustrationFilename {
            let url = AppPaths.illustrations.appendingPathComponent(illustrationFilename)
            if FileManager.default.fileExists(atPath: url.path) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderImage
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        placeholderImage
                    }
                }
            } else {
                workingImageOrPlaceholder
            }
        } else {
            workingImageOrPlaceholder
        }
    }

    @ViewBuilder
    private var workingImageOrPlaceholder: some View {
        let workingURL = AppPaths.working.appendingPathComponent(entry.workingImageFilename)
        if FileManager.default.fileExists(atPath: workingURL.path) {
            AsyncImage(url: workingURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholderImage
                @unknown default:
                    placeholderImage
                }
            }
        } else {
            placeholderImage
        }
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Image(systemName: "leaf")
                    .font(.largeTitle)
                    .foregroundColor(.gray.opacity(0.4))
            )
    }

    private var errorBadge: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(.red)
            .font(.title3)
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
            )
    }

    private var warningBadge: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundColor(.orange)
            .font(.title3)
            .background(
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
            )
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