import SwiftUI
import AppKit

struct EntryDetailView: View {
    @State var entry: Entry
    var onBack: () -> Void
    var onDeleted: (() -> Void)? = nil
    var onUpdated: ((Entry) -> Void)? = nil

    @State private var tab: PlateTab = .plate
    @State private var imageRefreshID = UUID()
    @State private var isRetrying = false
    @State private var isRecomposing = false
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var showNotes = false
    @State private var pipelineError: String?

    enum PlateTab { case plate, photo }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Hairline()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    plateColumn
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 56)
                        .padding(.vertical, 48)
                        .background(DS.paper)

                    Rectangle().fill(DS.hairlineSoft).frame(width: 1)

                    sidePanel
                        .frame(width: 360, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 48)
                        .background(DS.paper)
                }
            }
            .background(DS.paper)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.paper)
        .onAppear { updateWindowTitle() }
        .sheet(isPresented: $showNotes) {
            NotesEditor(entry: $entry, onSave: persistEntry)
        }
        .confirmationDialog(
            "Delete this plate?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: deleteEntry)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the entry, original photo, working copy, illustration, and plate. This cannot be undone.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .regular))
                    Text("Library")
                }
            }
            .buttonStyle(GhostButtonStyle())

            Spacer()

            MonoLabel(text: "PLATE \(plateNumber)", color: DS.muted)

            Spacer()

            HStack(spacing: 10) {
                Button("Notes") { showNotes = true }
                    .buttonStyle(QuietButtonStyle())
                Button(action: exportPlate) {
                    HStack(spacing: 6) {
                        if isExporting { ProgressView().controlSize(.small) }
                        Text("Export PNG")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(entry.illustrationFilename == nil || isExporting)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .background(DS.paper)
    }

    // MARK: - Plate column

    private var plateColumn: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 24) {
                tabButton(label: "Plate", isActive: tab == .plate) { tab = .plate }
                tabButton(label: "Original photograph", isActive: tab == .photo) { tab = .photo }
                Spacer()
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.hairlineSoft).frame(height: 1)
            }

            plateFrame
                .padding(.top, 28)
        }
    }

    private func tabButton(label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(label.uppercased())
                    .font(DS.sans(11.5, weight: .medium))
                    .tracking(1.4)
                    .foregroundColor(isActive ? DS.ink : DS.muted)
                Rectangle()
                    .fill(isActive ? DS.ink : Color.clear)
                    .frame(height: 1)
            }
            .padding(.top, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var plateFrame: some View {
        Group {
            if tab == .photo {
                ZStack {
                    DS.paper
                    Rectangle().stroke(DS.hairline, lineWidth: 1)
                    photoBody.padding(14)
                }
                .aspectRatio(3.0/4.0, contentMode: .fit)
            } else {
                PlateFrameView(entry: entry, refreshToken: imageRefreshID)
            }
        }
        .frame(maxWidth: 600)
    }

    @ViewBuilder
    private var photoBody: some View {
        let url = AppPaths.working.appendingPathComponent(entry.workingImageFilename)
        if FileManager.default.fileExists(atPath: url.path) {
            LocalImage(url: url, refreshToken: imageRefreshID) {
                PlatePlaceholder(label: "imported photograph")
            }
        } else {
            PlatePlaceholder(label: "imported photograph")
        }
    }

    // MARK: - Side panel

    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Identification")
                Text(entry.commonName)
                    .font(DS.serif(26, weight: .regular))
                    .foregroundColor(DS.ink)
                if !entry.scientificName.isEmpty {
                    Text(entry.scientificName)
                        .font(DS.serif(15, italic: true))
                        .foregroundColor(DS.inkSoft)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Hairline(color: DS.hairline)
                detailRow(label: "Family") {
                    Text(entry.family.isEmpty ? "—" : entry.family)
                        .font(DS.serif(13, italic: true))
                        .foregroundColor(DS.ink)
                }
                detailRow(label: "Captured") {
                    Text(displayCaptureDate)
                        .font(DS.sans(12.5))
                        .foregroundColor(DS.ink)
                }
                detailRow(label: "Plate") {
                    Text(plateNumber)
                        .font(DS.sans(12.5))
                        .foregroundColor(DS.ink)
                }
                detailRow(label: "Model certainty") {
                    HStack(spacing: 6) {
                        ConfidenceDot(level: entry.modelConfidence)
                        Text((entry.modelConfidence ?? "Unknown").capitalized)
                            .font(DS.sans(12.5))
                            .foregroundColor(DS.ink)
                    }
                }
            }

            if !visibleEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Visible characters")
                    FlowingTags(tags: visibleEvidence)
                }
            }

            if !alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Alternatives")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.commonName)
                                    .font(DS.sans(13))
                                    .foregroundColor(DS.ink)
                                if !alt.scientificName.isEmpty {
                                    Text(alt.scientificName)
                                        .font(DS.serif(12, italic: true))
                                        .foregroundColor(DS.mutedDeep)
                                }
                                if !alt.reason.isEmpty {
                                    Text(alt.reason)
                                        .font(DS.sans(11))
                                        .tracking(0.4)
                                        .foregroundColor(DS.muted)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.bottom, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(DS.hairlineSoft).frame(height: 1)
                            }
                        }
                    }
                }
            }

            if !entry.notes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Notes")
                    Text(entry.notes)
                        .font(DS.serif(14.5, italic: true))
                        .foregroundColor(DS.inkSoft)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Workspace")
                HStack(spacing: 10) {
                    Button(action: retryPipeline) {
                        HStack(spacing: 6) {
                            if isRetrying { ProgressView().controlSize(.small) }
                            Text(entry.plateFilename == nil ? "Run pipeline" : "Re-run pipeline")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isRetrying || isRecomposing || isDeleting)

                    Button(action: regenerateIllustration) {
                        HStack(spacing: 6) {
                            if isRecomposing { ProgressView().controlSize(.small) }
                            Text("Regenerate illustration")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(entry.identificationJson.isEmpty || isRetrying || isRecomposing || isDeleting)
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    HStack(spacing: 6) {
                        if isDeleting { ProgressView().controlSize(.small) }
                        Text("Delete entry")
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(isDeleting || isRetrying || isRecomposing)
                if let err = pipelineError {
                    Text(err)
                        .font(DS.sans(11))
                        .foregroundColor(DS.rust)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Hairline(color: DS.hairline)
                Text("Identification produced locally. Treat as a reference — verify with a field guide before consumption or handling.")
                    .font(DS.sans(11))
                    .tracking(0.4)
                    .lineSpacing(3)
                    .foregroundColor(DS.muted)
                    .padding(.top, 14)
            }
        }
    }

    private func detailRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(text: label, size: 9.5, color: DS.mutedDeep)
            Spacer(minLength: 16)
            content()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.hairlineSoft).frame(height: 1)
        }
    }

    // MARK: - Derived

    private var plateNumber: String {
        let suffix = String(entry.id.replacingOccurrences(of: "-", with: "").prefix(4)).uppercased()
        return "Nº \(suffix)"
    }

    private var footerDate: String {
        // Prefer captured-at, fall back to created-at.
        let iso = ISO8601DateFormatter()
        let date: Date? = (entry.capturedAt.flatMap { iso.date(from: $0) })
            ?? iso.date(from: entry.createdAt)
        guard let d = date else { return entry.createdAt }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }

    private var displayCaptureDate: String {
        let iso = ISO8601DateFormatter()
        let date: Date? = (entry.capturedAt.flatMap { iso.date(from: $0) })
            ?? iso.date(from: entry.createdAt)
        guard let d = date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }

    private struct AlternativeRow {
        let commonName: String
        let scientificName: String
        let reason: String
    }

    private var visibleEvidence: [String] {
        guard let data = entry.identificationJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let evidence = json["visible_evidence"] as? [String] else { return [] }
        return evidence
    }

    private var alternatives: [AlternativeRow] {
        guard let data = entry.identificationJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let alts = json["alternatives"] as? [[String: Any]] else { return [] }
        return alts.map { row in
            AlternativeRow(
                commonName: row["common_name"] as? String ?? "",
                scientificName: row["scientific_name"] as? String ?? "",
                reason: row["reason"] as? String ?? ""
            )
        }
    }

    // MARK: - Side effects

    private func updateWindowTitle() {
        NSApp.windows.first?.title = "Naturista — \(entry.commonName)"
    }

    private func persistEntry() {
        let snapshot = entry
        Task {
            do {
                try await DatabaseService.shared.saveEntry(snapshot)
                await MainActor.run { onUpdated?(snapshot) }
            } catch {
                await MainActor.run { pipelineError = error.localizedDescription }
            }
        }
    }

    private func deleteEntry() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isDeleting = true
        pipelineError = nil
        Task {
            do {
                try await PipelineService.shared.deleteEntry(entryId: entryId)
                await MainActor.run {
                    onDeleted?()
                    onBack()
                }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                    isDeleting = false
                }
            }
        }
    }

    private func regenerateIllustration() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isRecomposing = true
        pipelineError = nil
        Task {
            do {
                try await PipelineService.shared.regenerateIllustration(entryId: entryId)
                if let updated = try await DatabaseService.shared.fetchEntry(id: entry.id) {
                    await MainActor.run {
                        entry = updated
                        imageRefreshID = UUID()
                        isRecomposing = false
                        onUpdated?(updated)
                    }
                } else {
                    await MainActor.run { isRecomposing = false }
                }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                    isRecomposing = false
                }
            }
        }
    }

    private func retryPipeline() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isRetrying = true
        pipelineError = nil
        Task {
            do {
                try await PipelineService.shared.runFullPipeline(entryId: entryId)
            } catch {
                await MainActor.run { pipelineError = error.localizedDescription }
            }
            if let updated = try? await DatabaseService.shared.fetchEntry(id: entry.id) {
                await MainActor.run {
                    entry = updated
                    imageRefreshID = UUID()
                    onUpdated?(updated)
                }
            }
            await MainActor.run { isRetrying = false }
        }
    }

    private func exportPlate() {
        guard entry.illustrationFilename != nil else { return }
        isExporting = true
        pipelineError = nil

        let panel = NSSavePanel()
        panel.title = "Export Plate"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(entry.commonName)-plate.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            isExporting = false
            return
        }

        let snapshot = entry
        Task { @MainActor in
            do {
                try PlateCompositor.renderPNG(entry: snapshot, to: destination)
            } catch {
                pipelineError = "Failed to export: \(error.localizedDescription)"
            }
            isExporting = false
        }
    }
}

// Wraps the SwiftUI tag list so chips wrap onto multiple rows.
struct FlowingTags: View {
    let tags: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { TagChip(text: $0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let cap = ProposedViewSize(width: width, height: nil)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(cap)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }
        return CGSize(width: maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        let cap = ProposedViewSize(width: width, height: nil)
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(cap)
            if x + size.width > bounds.minX + width && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct NotesEditor: View {
    @Binding var entry: Entry
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Notes")
            Text(entry.commonName)
                .font(DS.serif(22))
                .foregroundColor(DS.ink)

            TextEditor(text: $draft)
                .font(DS.serif(14, italic: true))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(DS.paperDeep)
                .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
                .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Button("Save") {
                    entry.notes = draft
                    onSave()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 520, height: 380)
        .background(DS.paper)
        .onAppear { draft = entry.notes }
    }
}

// Adds a touch of editorial small-caps to the plate title.
private extension String {
    var smallCapsForHerbarium: String {
        // SwiftUI doesn't expose font-variant: small-caps cleanly across
        // serif renderers, so render uppercase as a near-equivalent.
        self.uppercased()
    }
}
