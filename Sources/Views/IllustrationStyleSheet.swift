import SwiftUI

// User-facing editor for the four Flux per-kingdom prompt templates and the
// Gemma identification-model picker. Lives behind the "Illustration style"
// trigger in the LibraryView sidebar. Edits are held in @State and only
// committed (UserDefaults / model swap) on Save.

struct IllustrationStyleSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let allKingdoms: [Kingdom] = [.plant, .animal, .fungus, .other]

    @State private var drafts: [Kingdom: String] = [:]
    @State private var errors: [Kingdom: String] = [:]
    @State private var showCloseConfirm = false
    @State private var showResetAllConfirm = false

    @State private var selectedModel: GemmaModel = GemmaModelStore.shared.selected
    @State private var selectedFluxQuant: FluxQuantizationPreference = FluxQuantizationStore.shared.selected
    @State private var preloadEnabled: Bool = GemmaPreloadStore.shared.enabled
    @State private var isDownloading = false
    @State private var downloadingModel: GemmaModel? = nil
    @State private var modelError: String? = nil
    @State private var pendingDelete: GemmaModel? = nil
    @State private var deletingModel: GemmaModel? = nil

    private var savedModel: GemmaModel { GemmaModelStore.shared.selected }
    private var modelChanged: Bool { selectedModel != savedModel }
    private var savedFluxQuant: FluxQuantizationPreference { FluxQuantizationStore.shared.selected }
    private var fluxQuantChanged: Bool { selectedFluxQuant != savedFluxQuant }
    private var savedPreloadEnabled: Bool { GemmaPreloadStore.shared.enabled }
    private var preloadChanged: Bool { preloadEnabled != savedPreloadEnabled }

    private var isDirty: Bool {
        if modelChanged || fluxQuantChanged || preloadChanged { return true }
        for kingdom in allKingdoms {
            let saved = IllustrationPromptStore.shared.template(for: kingdom)
            if (drafts[kingdom] ?? saved) != saved { return true }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    ForEach(allKingdoms, id: \.self) { kingdom in
                        editor(for: kingdom)
                    }
                    Hairline()
                    modelSection
                    Hairline()
                    fluxQuantizationSection
                    Hairline()
                    preloadSection
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
            }
            .background(DS.paper)
            Hairline()
            footer
        }
        .frame(width: 760, height: 720)
        .background(DS.paper)
        .overlay {
            if isDownloading {
                downloadOverlay
            }
        }
        .onAppear { loadDrafts() }
        .confirmModal(
            isPresented: $showCloseConfirm,
            title: "Discard unsaved changes?",
            message: "Your edits to the illustration prompts will be lost.",
            confirmLabel: "Discard",
            cancelLabel: "Keep editing",
            isDestructive: true
        ) {
            dismiss()
        }
        .confirmModal(
            isPresented: $showResetAllConfirm,
            title: "Reset all four prompts to defaults?",
            message: "Custom edits in this sheet will be replaced with the originals. Nothing is saved until you press Save.",
            confirmLabel: "Reset all",
            isDestructive: true
        ) {
            for kingdom in allKingdoms {
                drafts[kingdom] = IllustrationPrompts.defaultTemplate(for: kingdom)
                errors[kingdom] = nil
            }
        }
        .confirmModal(
            item: $pendingDelete,
            title: { model in "Delete \(model.displayName) files?" },
            message: { model in
                let isActive = model == GemmaModelStore.shared.selected
                let activeNote = isActive
                    ? " It is your current model, so the next identification will trigger a re-download."
                    : ""
                return "Frees ~\(formatGB(model.approxSizeGB)) of disk. The model stays in this list and can be re-downloaded later.\(activeNote)"
            },
            confirmLabel: "Delete files",
            isDestructive: true
        ) { model in
            Task { await performDelete(model) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Edit")
            Text("Illustration style")
                .font(DS.serif(28, weight: .regular))
                .foregroundColor(DS.ink)
                .kerning(-0.3)
            Text("Tweak the per-kingdom prompts that Flux uses to draw each plate. Changes apply to new generations only.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Per-kingdom editor

    @ViewBuilder
    private func editor(for kingdom: Kingdom) -> some View {
        let draft = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
        let isModified = draft != IllustrationPrompts.defaultTemplate(for: kingdom)
        let rowError = errors[kingdom]

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: kingdom.displayLabel)
                if isModified {
                    MonoLabel(text: "MODIFIED", size: 9.5, color: DS.amber)
                }
                Spacer()
                if isModified {
                    Button("Reset to default") {
                        drafts[kingdom] = IllustrationPrompts.defaultTemplate(for: kingdom)
                        errors[kingdom] = nil
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            TextEditor(text: Binding(
                get: { drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom) },
                set: {
                    drafts[kingdom] = $0
                    if errors[kingdom] != nil { errors[kingdom] = nil }
                }
            ))
            .font(DS.mono(11.5))
            .foregroundColor(DS.ink)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(rowError == nil ? DS.hairline : DS.rust, lineWidth: 1))
            .frame(minHeight: 130)

            HStack(spacing: 8) {
                MonoLabel(text: "VARIABLES")
                Text("{scientific_name} · {common_name} · {subject} · {pose} · {colors} · {setting}")
                    .font(DS.mono(10.5))
                    .foregroundColor(DS.muted)
            }

            if let rowError {
                Text(rowError)
                    .font(DS.sans(11))
                    .foregroundColor(DS.rust)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Identification model picker

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Identification model")
                if modelChanged {
                    MonoLabel(text: "MODIFIED", size: 9.5, color: DS.amber)
                }
            }

            Text("Pick the local VLM that handles photo identification. Save downloads weights on first use of an option.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(2)

            GemmaVariantList(selection: $selectedModel) { option in
                modelRowTrailing(option, installed: option.isInstalled, compat: option.compatibility())
            }

            if let modelError {
                Text(modelError)
                    .font(DS.sans(11))
                    .foregroundColor(DS.rust)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Illustration quantization picker

    private var fluxQuantizationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Illustration quality")
                if fluxQuantChanged {
                    MonoLabel(text: "MODIFIED", size: 9.5, color: DS.amber)
                }
            }

            Text("Pick how aggressively FLUX quantizes its weights. Higher fidelity costs more RAM during generation. Auto picks the best preset for this Mac.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(3)

            VStack(spacing: 0) {
                ForEach(FluxQuantizationPreference.allCases) { option in
                    fluxQuantRow(option)
                    if option != FluxQuantizationPreference.allCases.last { Hairline() }
                }
            }
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func fluxQuantRow(_ option: FluxQuantizationPreference) -> some View {
        let isSelected = selectedFluxQuant == option
        let compat = option.compatibility()
        let isDefault = option == .auto
        Button(action: {
            guard compat.isSelectable else { return }
            selectedFluxQuant = option
        }) {
            HStack(spacing: 14) {
                radioGlyph(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(option.displayName)
                            .font(DS.sans(13, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(DS.ink)
                        if isDefault {
                            MonoLabel(text: "DEFAULT", size: 9, color: DS.muted)
                        }
                        if option == .auto {
                            // Show what Auto resolves to on this Mac so the
                            // user knows what they'd get without picking.
                            let resolved = autoResolvedDisplayName()
                            MonoLabel(text: "→ \(resolved.uppercased())", size: 9, color: DS.muted)
                        }
                        compatibilityBadge(compat)
                    }
                    Text(option.blurb)
                        .font(DS.sans(11.5))
                        .foregroundColor(DS.inkSoft)
                        .lineLimit(2)
                    if let reason = compat.reason {
                        Text(reason)
                            .font(DS.sans(11))
                            .foregroundColor(compat.isSelectable ? DS.amber : DS.rust)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!compat.isSelectable)
        .background(isSelected ? DS.paper : Color.clear)
        .opacity(compat.isSelectable ? 1.0 : 0.55)
    }

    private func autoResolvedDisplayName() -> String {
        SystemCapability.current.physicalMemoryGB >= 48
            ? FluxQuantizationPreference.minimal.displayName
            : FluxQuantizationPreference.ultraMinimal.displayName
    }

    // MARK: - Startup preload toggle

    private var preloadSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Startup preload")
                if preloadChanged {
                    MonoLabel(text: "MODIFIED", size: 9.5, color: DS.amber)
                }
            }

            Text("Warm the identification model in the background at launch so the first identify is instant. Holds the full model resident at idle (≈3–17 GB depending on the selected Gemma). Off by default.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(3)

            Toggle(isOn: $preloadEnabled) {
                Text("Preload Gemma at launch")
                    .font(DS.sans(13, weight: .medium))
                    .foregroundColor(DS.ink)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func modelRow(_ option: GemmaModel) -> some View {
        let isSelected = selectedModel == option
        let installed = option.isInstalled
        let compat = option.compatibility()
        HStack(spacing: 0) {
            Button(action: {
                guard compat.isSelectable else { return }
                selectedModel = option
            }) {
                modelRowContent(option, isSelected: isSelected, installed: installed, compat: compat)
            }
            .buttonStyle(.plain)
            .disabled(!compat.isSelectable)

            modelRowTrailing(option, installed: installed, compat: compat)
        }
        .background(isSelected ? DS.paper : Color.clear)
        .opacity(compat.isSelectable ? 1.0 : 0.55)
    }

    @ViewBuilder
    private func modelRowContent(_ option: GemmaModel, isSelected: Bool, installed: Bool, compat: ModelCompatibility) -> some View {
        let isDefault = option == .gemma3_12b
        HStack(spacing: 14) {
            radioGlyph(isSelected: isSelected)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(option.displayName)
                        .font(DS.sans(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(DS.ink)
                    if isDefault {
                        MonoLabel(text: "DEFAULT", size: 9, color: DS.muted)
                    }
                    if installed {
                        MonoLabel(text: "INSTALLED", size: 9, color: DS.sage)
                    } else {
                        MonoLabel(text: "~\(formatGB(option.approxSizeGB))", size: 9, color: DS.amber)
                    }
                    compatibilityBadge(compat)
                }
                Text(option.blurb)
                    .font(DS.sans(11.5))
                    .foregroundColor(DS.inkSoft)
                    .lineLimit(2)
                if let reason = compat.reason {
                    Text(reason)
                        .font(DS.sans(11))
                        .foregroundColor(compat.isSelectable ? DS.amber : DS.rust)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.leading, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func compatibilityBadge(_ compat: ModelCompatibility) -> some View {
        switch compat {
        case .compatible:
            EmptyView()
        case .marginal:
            MonoLabel(text: "MAY BE SLOW", size: 9, color: DS.amber)
        case .incompatible:
            MonoLabel(text: "INCOMPATIBLE", size: 9, color: DS.rust)
        }
    }

    @ViewBuilder
    private func modelRowTrailing(_ option: GemmaModel, installed: Bool, compat: ModelCompatibility) -> some View {
        if installed {
            let isBusy = deletingModel == option
            Button(action: { pendingDelete = option }) {
                Text(isBusy ? "DELETING…" : "DELETE")
                    .font(DS.mono(9.5, weight: .regular))
                    .foregroundColor(DS.rust)
                    .tracking(0.4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        } else {
            Button(action: { Task { await performDownload(option) } }) {
                Text("DOWNLOAD")
                    .font(DS.mono(9.5, weight: .regular))
                    .foregroundColor(compat.isSelectable ? DS.amber : DS.muted)
                    .tracking(0.4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || !compat.isSelectable)
        }
    }

    private func radioGlyph(isSelected: Bool) -> some View {
        ZStack {
            Circle().stroke(isSelected ? DS.ink : DS.hairline, lineWidth: 1)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle().fill(DS.ink).frame(width: 7, height: 7)
            }
        }
    }

    private func formatGB(_ gb: Double) -> String {
        gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }

    // MARK: - Download overlay

    private var downloadOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView().controlSize(.large)
                Text("Downloading \(downloadingModel?.displayName ?? "model")…")
                    .font(DS.serif(16, weight: .regular))
                    .foregroundColor(DS.ink)
                Text("This is a one-time download. Keep the window open.")
                    .font(DS.sans(11.5))
                    .foregroundColor(DS.inkSoft)
            }
            .padding(28)
            .background(DS.paper)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Reset all to defaults") { showResetAllConfirm = true }
                .buttonStyle(GhostButtonStyle())

            Spacer()

            Button("Cancel") {
                if isDirty { showCloseConfirm = true } else { dismiss() }
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(isDownloading)

            Button("Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isDownloading)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .background(DS.paper)
    }

    // MARK: - Logic

    private func performDownload(_ model: GemmaModel) async {
        await MainActor.run {
            downloadingModel = model
            isDownloading = true
            modelError = nil
        }
        do {
            try await GemmaModelDownloader.shared.download(model)
            await MainActor.run {
                isDownloading = false
                downloadingModel = nil
            }
        } catch {
            await MainActor.run {
                isDownloading = false
                downloadingModel = nil
                modelError = error.localizedDescription
            }
        }
    }

    private func performDelete(_ model: GemmaModel) async {
        await MainActor.run {
            deletingModel = model
            modelError = nil
        }
        // If the model being deleted is the one currently loaded in the
        // subprocess, shut it down first so file handles release before unlink.
        if model == GemmaModelStore.shared.selected {
            await GemmaActor.shared.shutdown()
        }
        do {
            try await GemmaModelDownloader.shared.delete(model)
            await MainActor.run { deletingModel = nil }
        } catch {
            await MainActor.run {
                deletingModel = nil
                modelError = error.localizedDescription
            }
        }
    }

    private func loadDrafts() {
        for kingdom in allKingdoms {
            drafts[kingdom] = IllustrationPromptStore.shared.template(for: kingdom)
        }
        selectedModel = GemmaModelStore.shared.selected
        selectedFluxQuant = FluxQuantizationStore.shared.selected
        preloadEnabled = GemmaPreloadStore.shared.enabled
        modelError = nil
    }

    private func save() {
        // Validate prompts first; block on any unknown placeholders.
        var nextErrors: [Kingdom: String] = [:]
        for kingdom in allKingdoms {
            let draft = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
            let unknown = IllustrationPrompts.unknownPlaceholders(in: draft)
            if !unknown.isEmpty {
                let listed = unknown.sorted().map { "{\($0)}" }.joined(separator: ", ")
                nextErrors[kingdom] = "Unknown variable\(unknown.count > 1 ? "s" : "") \(listed). Allowed: {scientific_name}, {common_name}, {subject}, {pose}, {colors}, {setting}."
            }
        }
        errors = nextErrors
        if !nextErrors.isEmpty { return }

        let chosen = selectedModel
        let needsDownload = !chosen.isInstalled
        modelError = nil

        Task {
            if needsDownload {
                await MainActor.run {
                    downloadingModel = chosen
                    isDownloading = true
                }
                do {
                    try await GemmaModelDownloader.shared.download(chosen)
                } catch {
                    await MainActor.run {
                        isDownloading = false
                        downloadingModel = nil
                        modelError = error.localizedDescription
                    }
                    return
                }
                await MainActor.run {
                    isDownloading = false
                    downloadingModel = nil
                }
            }

            // Persist prompt overrides.
            var toPersist: [Kingdom: String] = [:]
            for kingdom in allKingdoms {
                toPersist[kingdom] = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
            }
            IllustrationPromptStore.shared.setOverrides(toPersist)

            // Persist model selection. If the model changed, shut down the
            // current Gemma subprocess so the next identify spawns a fresh one
            // with the new GEMMA_MODEL_PATH (read lazily via the env closure).
            // Then warm the new model in the background so the next import
            // doesn't pay the container build — but only if the user has
            // opted in to preload (otherwise the just-changed model would
            // silently sit in RAM).
            if chosen != GemmaModelStore.shared.selected {
                GemmaModelStore.shared.setSelected(chosen)
                await GemmaActor.shared.shutdown()
                if GemmaPreloadStore.shared.enabled {
                    Task.detached(priority: .utility) {
                        try? await ModelLease.shared.withExclusive(.identification) {
                            await GemmaActor.shared.preload()
                        }
                    }
                }
            }

            // Persist preload preference. Apply immediately: if just turned
            // on, warm now (matching launch behavior); if just turned off,
            // shut down to release RAM right away rather than waiting for
            // the next launch.
            let nextPreload = preloadEnabled
            if nextPreload != GemmaPreloadStore.shared.enabled {
                GemmaPreloadStore.shared.setEnabled(nextPreload)
                if nextPreload {
                    Task.detached(priority: .utility) {
                        guard GemmaModelStore.shared.selected.isInstalled else { return }
                        try? await ModelLease.shared.withExclusive(.identification) {
                            await GemmaActor.shared.preload()
                        }
                    }
                } else {
                    await GemmaActor.shared.shutdown()
                }
            }

            // Persist FLUX quantization preference. If it changed, drop the
            // resident pipeline so the next illustrate cold-loads with the
            // new preset.
            let chosenFlux = selectedFluxQuant
            if chosenFlux != FluxQuantizationStore.shared.selected {
                FluxQuantizationStore.shared.setSelected(chosenFlux)
                await FluxActor.shared.shutdown()
            }

            await MainActor.run { dismiss() }
        }
    }
}
