import SwiftUI
import AppKit

struct EntryDetailView: View {
    @State var entry: Entry
    var onDelete: ((Entry) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isSavingNotes = false
    @State private var isExporting = false
    @State private var isRetrying = false
    @State private var isRecomposing = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var exportError: String?
    @State private var retryError: String?
    @State private var recomposeError: String?
    @State private var deleteError: String?
    @State private var imageRefreshID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            mainImage
                .frame(maxHeight: 400)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.1))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection
                    badgesSection
                    notesSection
                    errorSection
                    actionButtonsSection
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var mainImage: some View {
        if let plateFilename = entry.plateFilename {
            let url = AppPaths.plates.appendingPathComponent(plateFilename)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalDiskImage(url: url, refreshToken: imageRefreshID, contentMode: .fit) {
                    illustrationImageView
                }
            } else {
                illustrationImageView
            }
        } else {
            illustrationImageView
        }
    }

    @ViewBuilder
    private var illustrationImageView: some View {
        if let illustrationFilename = entry.illustrationFilename {
            let url = AppPaths.illustrations.appendingPathComponent(illustrationFilename)
            if FileManager.default.fileExists(atPath: url.path) {
                LocalDiskImage(url: url, refreshToken: imageRefreshID, contentMode: .fit) {
                    workingImageView
                }
            } else {
                workingImageView
            }
        } else {
            workingImageView
        }
    }

    @ViewBuilder
    private var workingImageView: some View {
        let workingURL = AppPaths.working.appendingPathComponent(entry.workingImageFilename)
        if FileManager.default.fileExists(atPath: workingURL.path) {
            LocalDiskImage(url: workingURL, refreshToken: imageRefreshID, contentMode: .fit) {
                placeholderImageView
            }
        } else {
            placeholderImageView
        }
    }

    private var placeholderImageView: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.15))
            .overlay(
                Image(systemName: "leaf")
                    .font(.system(size: 60))
                    .foregroundColor(.gray.opacity(0.3))
            )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.commonName)
                .font(.title)
                .fontWeight(.bold)

            if !entry.scientificName.isEmpty {
                Text(entry.scientificName)
                    .font(.title3)
                    .italic()
                    .foregroundColor(.secondary)
            }

            if !entry.family.isEmpty {
                Text("Family: \(entry.family)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var badgesSection: some View {
        HStack(spacing: 12) {
            confidenceBadge
            statusBadge
        }
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        if let confidence = entry.modelConfidence {
            HStack(spacing: 4) {
                Image(systemName: confidenceIcon(for: confidence))
                Text("Model certainty: \(confidence)")
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(confidenceColor(for: confidence).opacity(0.15))
            .foregroundColor(confidenceColor(for: confidence))
            .clipShape(Capsule())
        }
    }

    private var statusBadge: some View {
        let (statusText, statusColor): (String, Color) = {
            switch entry.userStatus {
            case "confirmed": return ("Confirmed", .green)
            case "rejected": return ("Rejected", .red)
            case "failed": return ("Failed", .red)
            case "unreviewed": return ("Unreviewed", .gray)
            default: return (entry.userStatus.capitalized, .gray)
            }
        }()

        return HStack(spacing: 4) {
            Image(systemName: "person.fill.checkmark")
            Text("User status: \(statusText)")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.15))
        .foregroundColor(statusColor)
        .clipShape(Capsule())
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            TextEditor(text: $entry.notes)
                .font(.body)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .onChange(of: entry.notes) { _, newValue in
                    saveNotes(newValue)
                }

            if isSavingNotes {
                Text("Saving...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var errorSection: some View {
        Group {
            if entry.userStatus == "failed" {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Entry failed")
                            .font(.headline)
                            .foregroundColor(.red)
                    }

                    if !entry.notes.isEmpty {
                        Text(errorMessageFromNotes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Button(action: retryPipeline) {
                        HStack {
                            if isRetrying {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.trailing, 4)
                            }
                            Text("Retry Pipeline")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRetrying)

                    if let error = retryError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var errorMessageFromNotes: String {
        if let errorRange = entry.notes.range(of: "failed: ") {
            let afterFailed = entry.notes[errorRange.upperBound...]
            if let newlineRange = afterFailed.firstIndex(of: "\n") {
                return String(afterFailed[..<newlineRange])
            }
            return String(afterFailed)
        }
        return entry.notes
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: retryPipeline) {
                HStack {
                    if isRetrying {
                        ProgressView().controlSize(.small)
                    }
                    Text(entry.plateFilename == nil ? "Run Pipeline" : "Re-run Pipeline")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRetrying || isRecomposing || isDeleting)

            Button(action: recomposePlate) {
                HStack {
                    if isRecomposing {
                        ProgressView().controlSize(.small)
                    }
                    Text("Recompose Plate Only")
                }
            }
            .buttonStyle(.bordered)
            .disabled(entry.illustrationFilename == nil || isRetrying || isRecomposing || isDeleting)

            if let error = recomposeError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button("Export PNG", action: exportPlate)
                .buttonStyle(.bordered)
                .disabled(entry.plateFilename == nil || isExporting)

            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Divider().padding(.vertical, 4)

            Button(role: .destructive, action: { showDeleteConfirm = true }) {
                HStack {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    }
                    Image(systemName: "trash")
                    Text("Delete Entry")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(isDeleting || isRetrying || isRecomposing)
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteEntry)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the entry, original photo, working copy, illustration, and plate. This cannot be undone.")
            }

            if let error = deleteError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.top, 8)
    }

    private func deleteEntry() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isDeleting = true
        deleteError = nil

        Task {
            do {
                try await PipelineService.shared.deleteEntry(entryId: entryId)
                await MainActor.run {
                    onDelete?(entry)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    deleteError = error.localizedDescription
                    isDeleting = false
                }
            }
        }
    }

    private func recomposePlate() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isRecomposing = true
        recomposeError = nil

        Task {
            do {
                try await PipelineService.shared.recomposePlate(entryId: entryId)
                if let updated = try await DatabaseService.shared.fetchEntry(id: entry.id) {
                    await MainActor.run {
                        entry = updated
                        imageRefreshID = UUID()
                        isRecomposing = false
                    }
                } else {
                    await MainActor.run { isRecomposing = false }
                }
            } catch {
                await MainActor.run {
                    recomposeError = error.localizedDescription
                    isRecomposing = false
                }
            }
        }
    }

    private func confidenceIcon(for confidence: String) -> String {
        switch confidence {
        case "high": return "checkmark.circle.fill"
        case "medium": return "questionmark.circle.fill"
        case "low": return "exclamationmark.triangle.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private func confidenceColor(for confidence: String) -> Color {
        switch confidence {
        case "high": return .green
        case "medium": return .orange
        case "low": return .red
        default: return .gray
        }
    }

    private func saveNotes(_ notes: String) {
        Task {
            isSavingNotes = true
            var updatedEntry = entry
            updatedEntry.notes = notes
            do {
                try await DatabaseService.shared.saveEntry(updatedEntry)
                entry = updatedEntry
            } catch {
                print("Failed to save notes: \(error)")
            }
            isSavingNotes = false
        }
    }

    private func exportPlate() {
        guard let plateFilename = entry.plateFilename else { return }

        isExporting = true
        exportError = nil

        let panel = NSSavePanel()
        panel.title = "Export Plate"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(entry.commonName)-plate.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            isExporting = false
            return
        }

        let sourceURL = AppPaths.plates.appendingPathComponent(plateFilename)

        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: sourceURL, to: url)
        } catch {
            exportError = "Failed to export: \(error.localizedDescription)"
        }

        isExporting = false
    }

    private func retryPipeline() {
        isRetrying = true
        retryError = nil

        Task {
            do {
                try await PipelineService.shared.runFullPipeline(entryId: UUID(uuidString: entry.id)!)
                if let updatedEntry = try await DatabaseService.shared.fetchEntry(id: entry.id) {
                    await MainActor.run {
                        entry = updatedEntry
                        imageRefreshID = UUID()
                    }
                }
            } catch {
                await MainActor.run {
                    retryError = error.localizedDescription
                }
                if let updatedEntry = try await DatabaseService.shared.fetchEntry(id: entry.id) {
                    await MainActor.run {
                        entry = updatedEntry
                        imageRefreshID = UUID()
                    }
                }
            }
            await MainActor.run {
                isRetrying = false
            }
        }
    }
}

private struct LocalDiskImage<Fallback: View>: View {
    let url: URL
    let refreshToken: UUID
    let contentMode: ContentMode
    @ViewBuilder var fallback: () -> Fallback

    @State private var image: NSImage?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
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