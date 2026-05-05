import SwiftUI
import AppKit

struct EntryDetailView: View {
    @State var entry: Entry
    // When true, the regenerate options sheet auto-presents on first
    // appearance. Used by the library's right-click "Regenerate" path
    // so it lands on the same variant flow as the in-detail button.
    var openRegenerateOnAppear: Bool = false
    var onBack: () -> Void
    var onDeleted: (() -> Void)? = nil
    var onUpdated: ((Entry) -> Void)? = nil

    @State private var tab: PlateTab = .plate
    @State private var imageRefreshID = UUID()
    @State private var isRetrying = false
    @State private var isCorrecting = false
    @State private var isExporting = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var showNotes = false
    @State private var showCorrectionSheet = false
    @State private var correctionDraftCommon = ""
    @State private var correctionDraftScientific = ""
    @State private var pipelineError: String?
    @State private var exportMenuPresented = false
    @State private var isAddingTag = false
    @State private var tagDraft: String = ""
    @State private var allKnownTags: [String] = []
    @State private var promptSectionExpanded = false
    @State private var isEditingPrompt = false
    @State private var promptDraft: String = ""
    @State private var promptError: String?
    @State private var showRegenerateOptions = false
    @State private var editingField: EditableField? = nil
    @State private var editDraft: String = ""
    @FocusState private var editFocused: Bool

    enum PlateTab { case plate, photo }
    enum EditableField { case commonName, scientificName, family }

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
        .background(escapeShortcut)
        .onAppear {
            updateWindowTitle()
            loadKnownTags()
            if openRegenerateOnAppear {
                showRegenerateOptions = true
            }
        }
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
        .sheet(isPresented: $showRegenerateOptions) {
            RegenerateOptionsSheet(entry: entry, onAccepted: {
                Task { await reloadEntry() }
            })
        }
        .confirmModal(
            isPresented: $showDeleteConfirm,
            title: "Delete this plate?",
            message: "Removes the entry, original photo, working copy, illustration, and plate. This cannot be undone.",
            confirmLabel: "Delete",
            isDestructive: true
        ) {
            deleteEntry()
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
                    editableCommonName
                    editableScientificName
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
                .disabled(isCorrecting || isRetrying || isDeleting)
            }

            VStack(alignment: .leading, spacing: 0) {
                Hairline(color: DS.hairline)
                detailRow(label: "Family") {
                    editableFamily
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

            tagsSection

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

            illustrationPromptSection

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
                    .disabled(isRetrying || isCorrecting || isDeleting)

                    Button(action: { showRegenerateOptions = true }) {
                        Text("Regenerate illustration")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(entry.identification.result == nil || isRetrying || isCorrecting || isDeleting)
                }
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    HStack(spacing: 6) {
                        if isDeleting { ProgressView().controlSize(.small) }
                        Text("Delete entry")
                    }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(isDeleting || isRetrying || isCorrecting)
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

    // MARK: - Inline-editable fields

    @ViewBuilder
    private var editableCommonName: some View {
        if editingField == .commonName {
            TextField("", text: $editDraft)
                .textFieldStyle(.plain)
                .font(DS.serif(26, weight: .regular))
                .foregroundColor(DS.ink)
                .focused($editFocused)
                .onSubmit { commitEdit(.commonName) }
                .onExitCommand { cancelEdit() }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.effectiveCommonName ?? "Unidentified")
                    .font(DS.serif(26, weight: .regular))
                    .foregroundColor(DS.ink)
                if entry.isCommonNameEdited {
                    editedBadge
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                startEdit(.commonName, current: entry.effectiveCommonName ?? "")
            }
        }
    }

    @ViewBuilder
    private var editableScientificName: some View {
        if editingField == .scientificName {
            TextField("", text: $editDraft)
                .textFieldStyle(.plain)
                .font(DS.serif(15, italic: true))
                .foregroundColor(DS.inkSoft)
                .focused($editFocused)
                .onSubmit { commitEdit(.scientificName) }
                .onExitCommand { cancelEdit() }
        } else if let scientific = entry.effectiveScientificName, !scientific.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(scientific)
                    .font(DS.serif(15, italic: true))
                    .foregroundColor(DS.inkSoft)
                if entry.isScientificNameEdited {
                    editedBadge
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                startEdit(.scientificName, current: scientific)
            }
        }
    }

    @ViewBuilder
    private var editableFamily: some View {
        if editingField == .family {
            TextField("", text: $editDraft)
                .textFieldStyle(.plain)
                .font(DS.serif(13, italic: true))
                .foregroundColor(DS.ink)
                .focused($editFocused)
                .onSubmit { commitEdit(.family) }
                .onExitCommand { cancelEdit() }
        } else {
            let family = entry.effectiveFamily ?? ""
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(family.isEmpty ? "—" : family)
                    .font(DS.serif(13, italic: true))
                    .foregroundColor(DS.ink)
                if entry.isFamilyEdited {
                    editedBadge
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                startEdit(.family, current: family)
            }
        }
    }

    private var editedBadge: some View {
        Text("edited")
            .font(DS.sans(10))
            .tracking(0.4)
            .foregroundColor(DS.muted)
    }

    private func startEdit(_ field: EditableField, current: String) {
        editDraft = current
        editingField = field
        // Defer focus until the TextField is actually mounted.
        DispatchQueue.main.async { editFocused = true }
    }

    private func cancelEdit() {
        editingField = nil
        editDraft = ""
        editFocused = false
    }

    private func commitEdit(_ field: EditableField) {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let aiValue: String
        switch field {
        case .commonName: aiValue = entry.identification.commonName ?? ""
        case .scientificName: aiValue = entry.identification.scientificName ?? ""
        case .family: aiValue = entry.identification.family ?? ""
        }
        // If the user typed the AI value verbatim (or cleared the field),
        // clear the override instead of persisting a redundant duplicate.
        let valueForDB: String? = trimmed.isEmpty || trimmed == aiValue ? nil : trimmed
        let id = entry.id
        editingField = nil
        editDraft = ""
        editFocused = false
        Task {
            do {
                let updated: Entry?
                switch field {
                case .commonName:
                    updated = try await DatabaseService.shared.setEditedCommonName(id: id, value: valueForDB)
                case .scientificName:
                    updated = try await DatabaseService.shared.setEditedScientificName(id: id, value: valueForDB)
                case .family:
                    updated = try await DatabaseService.shared.setEditedFamily(id: id, value: valueForDB)
                }
                if let updated {
                    await MainActor.run {
                        entry = updated
                        onUpdated?(updated)
                        updateWindowTitle()
                    }
                }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                }
            }
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
            return Text("Identification produced locally. Treat as a reference: verify with a field guide before consumption or handling.")
        case .animal:
            return Text("Identification produced locally. Treat as a reference: do not approach, handle, or feed wildlife based on this.")
        case .fungus:
            return Text("Identification produced locally. ")
                + Text("Never eat a wild mushroom based on this identification.").bold()
                + Text(" Many edible species have lethal lookalikes.")
        case .other:
            return Text("Identification produced locally. Treat as a reference.")
        }
    }

    // MARK: - Illustration prompt override

    @ViewBuilder
    private var illustrationPromptSection: some View {
        let busy = isRetrying || isCorrecting || isDeleting
        let hasOverride = (entry.customFluxPrompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        let effectivePrompt = currentEffectivePrompt()
        let canEdit = entry.identification.result != nil

        VStack(alignment: .leading, spacing: 10) {
            Button(action: { promptSectionExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: promptSectionExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(DS.muted)
                    Eyebrow(text: "Illustration prompt")
                    if hasOverride {
                        MonoLabel(text: "OVERRIDE", size: 9.5, color: DS.amber)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if promptSectionExpanded {
                if !canEdit {
                    Text("Run identification first to see and edit the prompt.")
                        .font(DS.sans(11.5))
                        .foregroundColor(DS.inkSoft)
                } else if isEditingPrompt {
                    TextEditor(text: $promptDraft)
                        .font(DS.mono(11.5))
                        .foregroundColor(DS.ink)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(DS.paperDeep)
                        .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
                        .frame(minHeight: 160)

                    HStack(spacing: 10) {
                        Button("Save") { applyPromptDraft() }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(busy)
                        Button("Cancel") {
                            isEditingPrompt = false
                            promptDraft = ""
                            promptError = nil
                        }
                        .buttonStyle(GhostButtonStyle())
                        .disabled(busy)
                    }
                } else {
                    Text(effectivePrompt)
                        .font(DS.mono(11.5))
                        .foregroundColor(DS.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.paperDeep)
                        .overlay(Rectangle().stroke(DS.hairlineSoft, lineWidth: 1))

                    HStack(spacing: 10) {
                        Button("Edit prompt") {
                            promptDraft = effectivePrompt
                            isEditingPrompt = true
                            promptError = nil
                        }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(busy)

                        if hasOverride {
                            Button("Reset to template") { resetPromptOverride() }
                                .buttonStyle(GhostButtonStyle())
                                .disabled(busy)
                        }
                    }

                    Text(hasOverride
                        ? "This entry uses a custom prompt. Re-identifying won't update it: use Reset to follow the template again."
                        : "Generated from the kingdom template and Gemma's photo description. Edit to override per-entry.")
                        .font(DS.sans(11))
                        .foregroundColor(DS.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let promptError {
                    Text(promptError)
                        .font(DS.sans(11))
                        .foregroundColor(DS.rust)
                        .lineLimit(3)
                }
            }
        }
    }

    private func currentEffectivePrompt() -> String {
        if let override = entry.customFluxPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        guard let result = entry.identification.result else { return "" }
        let template = IllustrationPromptStore.shared.template(
            for: Kingdom.parse(result.kingdom)
        )
        return IllustrationPrompts.render(template: template, identification: result)
    }

    private func applyPromptDraft() {
        let snapshotId = entry.id
        let draft = promptDraft
        Task {
            do {
                _ = try await DatabaseService.shared.setCustomFluxPrompt(
                    id: snapshotId,
                    prompt: draft
                )
                if let updated = try await DatabaseService.shared.fetchEntry(id: snapshotId) {
                    await MainActor.run {
                        entry = updated
                        isEditingPrompt = false
                        promptDraft = ""
                        promptError = nil
                        onUpdated?(updated)
                    }
                }
            } catch {
                await MainActor.run { promptError = error.localizedDescription }
            }
        }
    }

    private func resetPromptOverride() {
        let snapshotId = entry.id
        Task {
            do {
                _ = try await DatabaseService.shared.setCustomFluxPrompt(
                    id: snapshotId,
                    prompt: nil
                )
                if let updated = try await DatabaseService.shared.fetchEntry(id: snapshotId) {
                    await MainActor.run {
                        entry = updated
                        promptError = nil
                        onUpdated?(updated)
                    }
                }
            } catch {
                await MainActor.run { promptError = error.localizedDescription }
            }
        }
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Tags")
            FlowLayout(spacing: 6) {
                ForEach(entry.tags, id: \.self) { tag in
                    RemovableTagChip(text: tag) { removeTag(tag) }
                }
                if isAddingTag {
                    TagInputField(
                        text: $tagDraft,
                        suggestions: tagSuggestions,
                        onCommit: {
                            commitTagDraft()
                        },
                        onCancel: {
                            tagDraft = ""
                            isAddingTag = false
                        }
                    )
                } else {
                    Button {
                        isAddingTag = true
                        tagDraft = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .regular))
                            Text("Add tag")
                                .font(DS.sans(10.5))
                                .tracking(0.4)
                        }
                        .foregroundColor(DS.muted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(DS.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // Up to 6 prefix-matching tags from the user's existing vocabulary,
    // excluding ones already on this entry. Case-sensitive (matches the
    // sidebar's grouping behaviour).
    private var tagSuggestions: [String] {
        let draft = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return [] }
        let used = Set(entry.tags)
        return allKnownTags
            .filter { !used.contains($0) && $0.hasPrefix(draft) && $0 != draft }
            .prefix(6)
            .map { $0 }
    }

    private func commitTagDraft() {
        let candidate = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            tagDraft = ""
            isAddingTag = false
        }
        guard !candidate.isEmpty, !entry.tags.contains(candidate) else { return }
        persistTags(entry.tags + [candidate])
    }

    private func removeTag(_ tag: String) {
        persistTags(entry.tags.filter { $0 != tag })
    }

    private func persistTags(_ newTags: [String]) {
        let id = entry.id
        let previous = entry.tags
        // Optimistic local flip; reconcile from DB on response.
        var optimistic = entry
        optimistic.setTags(newTags)
        entry = optimistic
        Task {
            do {
                let updated = try await DatabaseService.shared.setTags(id: id, tags: newTags)
                if let updated {
                    await MainActor.run {
                        entry = updated
                        onUpdated?(updated)
                        // Refresh known-tags so a brand-new tag becomes
                        // suggestable on the next add without a round-trip.
                        loadKnownTags()
                    }
                }
            } catch {
                await MainActor.run {
                    var revert = entry
                    revert.setTags(previous)
                    entry = revert
                    pipelineError = error.localizedDescription
                }
            }
        }
    }

    private func loadKnownTags() {
        Task {
            do {
                let entries = try await DatabaseService.shared.fetchAllEntries()
                var seen = Set<String>()
                var ordered: [String] = []
                for e in entries {
                    for t in e.tags where !seen.contains(t) {
                        seen.insert(t)
                        ordered.append(t)
                    }
                }
                ordered.sort()
                await MainActor.run { allKnownTags = ordered }
            } catch {
                // Silent — autocomplete is best-effort.
            }
        }
    }

    // Hidden button that maps Esc to the back action. Using
    // `.keyboardShortcut(.cancelAction)` (the same role Cancel buttons
    // use) is what keeps this sandbox-safe and stops AppKit from
    // beeping at an unhandled keystroke. Sheets and confirmation
    // dialogs install their own cancel buttons, so when one is open it
    // wins and Esc dismisses the sheet first — exactly what we want.
    private var escapeShortcut: some View {
        Button("Back to library") { handleEscape() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    // Esc: cancel the innermost edit if one is open, otherwise return
    // to the library.
    private func handleEscape() {
        if editingField != nil {
            cancelEdit()
            return
        }
        if isEditingPrompt {
            isEditingPrompt = false
            promptDraft = ""
            promptError = nil
            return
        }
        if isAddingTag {
            tagDraft = ""
            isAddingTag = false
            return
        }
        onBack()
    }

    // MARK: - Side effects

    private func updateWindowTitle() {
        NSApp.windows.first?.title = "Naturista: \(entry.effectiveCommonName ?? "Entry")"
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
        // Pre-fill drafts with the current effective values so the user edits
        // rather than retypes — and so a user who already edited the name
        // inline sees their corrected value, not the stale AI guess. Empty
        // defaults if the entry has no result yet (rare: the Edit button is
        // hidden in that flow path, but defensive).
        correctionDraftCommon = entry.effectiveCommonName ?? ""
        correctionDraftScientific = entry.effectiveScientificName ?? ""
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

    // Pull the latest entry from the database and refresh the plate
    // image. Used by the variant accept callback : the pipeline
    // already saved the swapped illustration, we just need the view
    // model to catch up.
    private func reloadEntry() async {
        guard let updated = try? await DatabaseService.shared.fetchEntry(id: entry.id) else { return }
        await MainActor.run {
            entry = updated
            imageRefreshID = UUID()
            onUpdated?(updated)
        }
    }

    private func retryPipeline() {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        isRetrying = true
        pipelineError = nil
        Task {
            do {
                try await EntryPipeline.production.illustrate(
                    entryId: entryId,
                    preserveLayout: false
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
        panel.nameFieldStringValue = "\(entry.effectiveCommonName ?? "plate")-plate.png"
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
        panel.nameFieldStringValue = "\(entry.effectiveCommonName ?? "plate")-image.png"
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
            Text(entry.effectiveCommonName ?? "Notes")
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

// TagChip with an always-visible × for removal — dimmed until hover so a
// quiet row of chips reads cleanly, but the affordance is discoverable
// without the user having to find it by mousing over.
private struct RemovableTagChip: View {
    let text: String
    var onRemove: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(DS.sans(10.5))
                .tracking(0.4)
                .foregroundColor(DS.inkSoft)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(DS.muted)
                    .opacity(hovered ? 1.0 : 0.5)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(DS.paperDeep)
        .overlay(Rectangle().stroke(DS.hairlineSoft, lineWidth: 1))
        .onHover { hovered = $0 }
    }
}

// Inline tag input — TextField shaped like a chip, with a popover of
// autocomplete suggestions below. Commits on Return (or selecting a
// suggestion); cancels on Escape.
private struct TagInputField: View {
    @Binding var text: String
    let suggestions: [String]
    var onCommit: () -> Void
    var onCancel: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .font(DS.sans(10.5))
            .foregroundColor(DS.ink)
            .frame(minWidth: 60)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.ink, lineWidth: 1))
            .onSubmit { onCommit() }
            .onExitCommand { onCancel() }
            .onAppear { focused = true }
            .popover(isPresented: .constant(!suggestions.isEmpty && focused), arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { s in
                        Button {
                            text = s
                            onCommit()
                        } label: {
                            Text(s)
                                .font(DS.sans(11.5))
                                .foregroundColor(DS.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minWidth: 140)
                .background(DS.paper)
            }
    }
}
