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
    @State private var isCorrecting = false
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var showNotes = false
    @State private var showCorrectionSheet = false
    @State private var correctionDraftCommon = ""
    @State private var correctionDraftScientific = ""
    @State private var pipelineError: String?
    @State private var preserveLayout = false
    @State private var exportMenuPresented = false

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
        .sheet(isPresented: $showCorrectionSheet) {
            CorrectIdentificationSheet(
                commonName: $correctionDraftCommon,
                scientificName: $correctionDraftScientific,
                onCancel: { showCorrectionSheet = false },
                onSave: submitCorrection,
                onAppearPreload: { Task { await GemmaActor.shared.preload() } }
            )
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
                Button(action: togglePin) {
                    HStack(spacing: 6) {
                        Image(systemName: entry.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 11, weight: .regular))
                            .rotationEffect(.degrees(45))
                        Text(entry.pinned ? "Pinned" : "Pin")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                Button("Notes") { showNotes = true }
                    .buttonStyle(QuietButtonStyle())
                Button(action: { exportMenuPresented.toggle() }) {
                    HStack(spacing: 6) {
                        if isExporting { ProgressView().controlSize(.small) }
                        Text("Export")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .regular))
                            .foregroundColor(DS.muted)
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(entry.illustrationFilename == nil || isExporting)
                .popover(isPresented: $exportMenuPresented, arrowEdge: .top) {
                    ExportMenuView(
                        onExportPlate: { exportMenuPresented = false; exportPlate() },
                        onExportImage: { exportMenuPresented = false; exportImage() }
                    )
                }
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
        let id = entry.identification
        return VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Identification")
                    Text(id.commonName ?? "Unidentified")
                        .font(DS.serif(26, weight: .regular))
                        .foregroundColor(DS.ink)
                    if let scientific = id.scientificName, !scientific.isEmpty {
                        Text(scientific)
                            .font(DS.serif(15, italic: true))
                            .foregroundColor(DS.inkSoft)
                    }
                }
                Spacer(minLength: 0)
                Button(action: startCorrection) {
                    HStack(spacing: 6) {
                        if isCorrecting { ProgressView().controlSize(.small) }
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .regular))
                        Text("Edit ID")
                    }
                }
                .buttonStyle(QuietButtonStyle())
                .disabled(isCorrecting || isRetrying || isRecomposing || isDeleting)
            }

            VStack(alignment: .leading, spacing: 0) {
                Hairline(color: DS.hairline)
                detailRow(label: "Family") {
                    let family = id.family ?? ""
                    Text(family.isEmpty ? "—" : family)
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

            if !id.visibleEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: id.kingdom.visibleEvidenceLabel)
                    FlowingTags(tags: id.visibleEvidence)
                }
            }

            if !id.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Alternatives")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(id.alternatives.enumerated()), id: \.offset) { _, alt in
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

                preserveLayoutToggle

                HStack(spacing: 10) {
                    Button(action: retryPipeline) {
                        HStack(spacing: 6) {
                            if isRetrying { ProgressView().controlSize(.small) }
                            Text(entry.plateFilename == nil ? "Run pipeline" : "Re-run pipeline")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(isRetrying || isRecomposing || isCorrecting || isDeleting)

                    Button(action: regenerateIllustration) {
                        HStack(spacing: 6) {
                            if isRecomposing { ProgressView().controlSize(.small) }
                            Text("Regenerate illustration")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(entry.identification.result == nil || isRetrying || isRecomposing || isCorrecting || isDeleting)
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    HStack(spacing: 6) {
                        if isDeleting { ProgressView().controlSize(.small) }
                        Text("Delete entry")
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(isDeleting || isRetrying || isRecomposing || isCorrecting)
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
                safetyFooter
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

    // Kingdom-specific safety boilerplate for the panel footer. The fungus
    // case bolds "Never eat" — mushroom misidentification has lethal stakes
    // and a polite hedge would undersell that.
    private var safetyFooter: Text {
        switch entry.identification.kingdom {
        case .plant:
            return Text("Identification produced locally. Treat as a reference — verify with a field guide before consumption or handling.")
        case .animal:
            return Text("Identification produced locally. Treat as a reference — do not approach, handle, or feed wildlife based on this.")
        case .fungus:
            return Text("Identification produced locally. ")
                + Text("Never eat a wild mushroom based on this identification.").bold()
                + Text(" Many edible species have lethal lookalikes.")
        case .other:
            return Text("Identification produced locally. Treat as a reference.")
        }
    }

    // MARK: - Preserve-layout toggle

    private var preserveLayoutToggle: some View {
        let busy = isRetrying || isRecomposing || isCorrecting || isDeleting
        return Button(action: {
            guard !busy else { return }
            preserveLayout.toggle()
        }) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Rectangle()
                        .stroke(preserveLayout ? DS.ink : DS.hairline, lineWidth: 1)
                        .frame(width: 13, height: 13)
                    if preserveLayout {
                        Rectangle()
                            .fill(DS.ink)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Match photograph composition")
                            .font(DS.sans(12.5, weight: preserveLayout ? .semibold : .medium))
                            .foregroundColor(DS.ink)
                        MonoLabel(text: "MUCH SLOWER", size: 9, color: DS.amber)
                    }
                    Text("Re-runs FLUX with the original photograph as a visual reference.")
                        .font(DS.sans(11))
                        .foregroundColor(DS.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .padding(.bottom, 4)
    }

    // MARK: - Side effects

    private func updateWindowTitle() {
        NSApp.windows.first?.title = "Naturista — \(entry.identification.commonName ?? "Entry")"
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

    private func togglePin() {
        let target = !entry.pinned
        let id = entry.id
        // Optimistic local flip; reconcile from DB on response.
        entry.pinned = target
        Task {
            do {
                let updated = try await DatabaseService.shared.setPinned(id: id, pinned: target)
                if let updated {
                    await MainActor.run {
                        entry = updated
                        onUpdated?(updated)
                    }
                }
            } catch {
                await MainActor.run {
                    entry.pinned = !target
                    pipelineError = error.localizedDescription
                }
            }
        }
    }

    private func deleteEntry() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isDeleting = true
        pipelineError = nil
        Task {
            do {
                try await EntryPipeline.production.delete(entryId: entryId)
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

    private func startCorrection() {
        // Pre-fill drafts with the current identification so the user edits
        // rather than retypes. Empty defaults if the entry has no result yet
        // (rare — the Edit button is hidden in that flow path, but defensive).
        correctionDraftCommon = entry.identification.commonName ?? ""
        correctionDraftScientific = entry.identification.scientificName ?? ""
        showCorrectionSheet = true
    }

    private func submitCorrection() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        let trimmedCommon = correctionDraftCommon.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScientific = correctionDraftScientific.trimmingCharacters(in: .whitespacesAndNewlines)
        let common: String? = trimmedCommon.isEmpty ? nil : trimmedCommon
        let scientific: String? = trimmedScientific.isEmpty ? nil : trimmedScientific
        guard common != nil || scientific != nil else { return }

        showCorrectionSheet = false
        isCorrecting = true
        pipelineError = nil
        Task {
            do {
                try await EntryPipeline.production.correctIdentification(
                    entryId: entryId,
                    userCommonName: common,
                    userScientificName: scientific
                )
                if let updated = try await DatabaseService.shared.fetchEntry(id: entry.id) {
                    await MainActor.run {
                        entry = updated
                        imageRefreshID = UUID()
                        isCorrecting = false
                        onUpdated?(updated)
                        updateWindowTitle()
                    }
                } else {
                    await MainActor.run { isCorrecting = false }
                }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                    isCorrecting = false
                }
            }
        }
    }

    private func regenerateIllustration() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isRecomposing = true
        pipelineError = nil
        let useReferencePhoto = preserveLayout
        Task {
            do {
                try await EntryPipeline.production.regenerate(
                    entryId: entryId,
                    preserveLayout: useReferencePhoto
                )
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
        let useReferencePhoto = preserveLayout
        Task {
            do {
                try await EntryPipeline.production.illustrate(
                    entryId: entryId,
                    preserveLayout: useReferencePhoto
                )
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
        panel.nameFieldStringValue = "\(entry.identification.commonName ?? "plate")-plate.png"
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

    private func exportImage() {
        guard let filename = entry.illustrationFilename else { return }
        let source = AppPaths.illustrations.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return }

        isExporting = true
        pipelineError = nil

        let panel = NSSavePanel()
        panel.title = "Export Image"
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(entry.identification.commonName ?? "plate")-image.png"
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let destination = panel.url else {
            isExporting = false
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            pipelineError = "Failed to export: \(error.localizedDescription)"
        }
        isExporting = false
    }
}

private struct ExportMenuView: View {
    var onExportPlate: () -> Void
    var onExportImage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Export")
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            MenuRow(title: "Export plate", action: onExportPlate)
            MenuRow(title: "Export image", action: onExportImage)
        }
        .frame(width: 220)
        .padding(.bottom, 6)
        .background(DS.paper)
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
            Text(entry.identification.commonName ?? "Notes")
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
