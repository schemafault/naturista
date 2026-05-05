import SwiftUI

// Per-image regenerate sheet. Lets the user pick one of three quality
// presets (Fast / Refined / High detail) or open Advanced to tweak
// steps, guidance, and frame size directly. Each Generate produces a
// new variant alongside the existing illustration; the user reviews
// the two and picks Keep or Discard. Discarded variants get cleaned
// up; kept variants overwrite the entry's canonical illustration.
//
// Quantization is intentionally absent here: it's a model-load knob,
// not a per-image one. Stays in IllustrationStyleSheet.

struct RegenerateOptionsSheet: View {
    let entry: Entry
    var onAccepted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    enum Preset: String, CaseIterable, Identifiable {
        case fast, refined, highDetail
        var id: String { rawValue }

        var label: String {
            switch self {
            case .fast: return "Fast"
            case .refined: return "Refined"
            case .highDetail: return "High detail"
            }
        }

        var blurb: String {
            switch self {
            case .fast: return "4 steps · 1024². Same as the standard pipeline."
            case .refined: return "6 steps · 1024². Sharper detail, ~50% slower."
            case .highDetail: return "8 steps · 1280². Best fidelity, ~3× slower."
            }
        }

        var params: FluxGenerationParams {
            switch self {
            case .fast: return FluxGenerationParams(width: 1024, height: 1024, steps: 4, guidance: 1.0)
            case .refined: return FluxGenerationParams(width: 1024, height: 1024, steps: 6, guidance: 1.0)
            case .highDetail: return FluxGenerationParams(width: 1280, height: 1280, steps: 8, guidance: 1.2)
            }
        }
    }

    enum Phase {
        case configuring
        case generating
        case reviewing(variantPath: String)
        case error(String)
    }

    @State private var preset: Preset = .fast
    @State private var advancedExpanded = false
    @State private var customSteps: Int = 4
    @State private var customGuidance: Double = 1.0
    @State private var customSize: Int = 1024
    @State private var preserveLayout: Bool = false
    @State private var phase: Phase = .configuring
    @State private var canonicalRefreshToken = UUID()
    @State private var variantRefreshToken = UUID()
    @State private var generationTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                content
                    .padding(.horizontal, 36)
                    .padding(.vertical, 24)
            }
            .background(DS.paper)
            Hairline()
            footer
        }
        .frame(width: 760, height: 720)
        .background(DS.paper)
        .onAppear { syncCustomFromPreset() }
        .onDisappear {
            // If the modal is dismissed mid-generate or with a variant
            // still pending review, scrub the file so we don't leak it.
            generationTask?.cancel()
            if case .reviewing(let path) = phase {
                Task { await EntryPipeline.production.discardVariant(variantPath: path) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Regenerate")
            Text("Plate options")
                .font(DS.serif(28, weight: .regular))
                .foregroundColor(DS.ink)
                .kerning(-0.3)
            Text("Pick a quality preset (or open Advanced) and generate a new variant. The current plate stays intact until you press Keep.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .configuring, .generating, .error:
            VStack(alignment: .leading, spacing: 24) {
                presetSection
                advancedSection
                preserveLayoutToggle
                if case .error(let message) = phase {
                    Text(message)
                        .font(DS.sans(11.5))
                        .foregroundColor(DS.rust)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .reviewing(let variantPath):
            comparison(variantPath: variantPath)
        }
    }

    // MARK: - Preset section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Quality preset")
            VStack(spacing: 0) {
                ForEach(Preset.allCases) { option in
                    presetRow(option)
                    if option != Preset.allCases.last { Hairline() }
                }
            }
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func presetRow(_ option: Preset) -> some View {
        let isSelected = preset == option
        Button(action: {
            preset = option
            syncCustomFromPreset()
        }) {
            HStack(spacing: 14) {
                radioGlyph(isSelected: isSelected)
                VStack(alignment: .leading, spacing: 3) {
                    Text(option.label)
                        .font(DS.sans(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(DS.ink)
                    Text(option.blurb)
                        .font(DS.sans(11.5))
                        .foregroundColor(DS.inkSoft)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? DS.paper : Color.clear)
        .disabled(isBusy)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { advancedExpanded.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(DS.muted)
                    Eyebrow(text: "Advanced")
                    if advancedDeviatesFromPreset {
                        MonoLabel(text: "CUSTOM", size: 9.5, color: DS.amber)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 18) {
                    advancedRow(label: "Denoising steps", valueText: "\(customSteps)") {
                        Stepper(value: $customSteps, in: 4...12) {
                            EmptyView()
                        }
                        .labelsHidden()
                    }
                    advancedRow(
                        label: "Prompt adherence",
                        valueText: String(format: "%.1f", customGuidance)
                    ) {
                        Slider(value: $customGuidance, in: 0.5...2.5, step: 0.1)
                            .frame(width: 180)
                    }
                    advancedRow(label: "Frame size", valueText: "\(customSize)²") {
                        Picker("", selection: $customSize) {
                            Text("1024").tag(1024)
                            Text("1280").tag(1280)
                            Text("1536").tag(1536)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    Text("Higher steps and larger sizes scale generation time. 1280² runs ~1.6× longer than 1024²; 1536² roughly doubles it.")
                        .font(DS.sans(11))
                        .foregroundColor(DS.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(DS.paperDeep)
                .overlay(Rectangle().stroke(DS.hairlineSoft, lineWidth: 1))
                .disabled(isBusy)
            }
        }
    }

    private func advancedRow<Control: View>(
        label: String,
        valueText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(DS.sans(12.5))
                .foregroundColor(DS.ink)
                .frame(width: 150, alignment: .leading)
            control()
            Spacer(minLength: 8)
            Text(valueText)
                .font(DS.mono(11.5))
                .foregroundColor(DS.inkSoft)
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    // MARK: - Preserve-layout toggle

    private var preserveLayoutToggle: some View {
        Button(action: {
            guard !isBusy else { return }
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
                    Text("Routes FLUX through image-to-image with the original photograph as a visual reference.")
                        .font(DS.sans(11))
                        .foregroundColor(DS.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: - Comparison

    @ViewBuilder
    private func comparison(variantPath: String) -> some View {
        let canonicalURL = entry.illustrationFilename.map {
            AppPaths.illustrations.appendingPathComponent($0)
        }
        let variantURL = URL(fileURLWithPath: variantPath)

        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Compare")
            HStack(alignment: .top, spacing: 18) {
                comparisonTile(label: "Current plate", url: canonicalURL, token: canonicalRefreshToken)
                comparisonTile(label: "New variant", url: variantURL, token: variantRefreshToken, accent: true)
            }
            Text("Keep replaces the saved plate with the new variant and refreshes the gallery thumbnail.")
                .font(DS.sans(11))
                .foregroundColor(DS.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func comparisonTile(label: String, url: URL?, token: UUID, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(DS.sans(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundColor(accent ? DS.ink : DS.muted)
                if accent {
                    Rectangle().fill(DS.amber).frame(width: 14, height: 1)
                }
            }
            ZStack {
                DS.paperDeep
                if let url, FileManager.default.fileExists(atPath: url.path) {
                    LocalImage(url: url, refreshToken: token) {
                        PlatePlaceholder(label: label.lowercased())
                    }
                    .padding(10)
                } else {
                    PlatePlaceholder(label: label.lowercased())
                        .padding(10)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(Rectangle().stroke(accent ? DS.ink : DS.hairline, lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch phase {
        case .configuring, .error:
            HStack(spacing: 14) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button(action: startGeneration) {
                    Text("Generate variant")
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(DS.paper)
        case .generating:
            HStack(spacing: 14) {
                Button("Cancel") { cancelGeneration() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Generating…")
                        .font(DS.sans(12.5))
                        .foregroundColor(DS.inkSoft)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(DS.paper)
        case .reviewing:
            HStack(spacing: 14) {
                Button("Discard") { discardAndReturn() }
                    .buttonStyle(GhostButtonStyle())
                Button("Generate again") { regenerate() }
                    .buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Keep") { acceptAndDismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(DS.paper)
        }
    }

    // MARK: - Logic

    private var isBusy: Bool {
        if case .generating = phase { return true }
        return false
    }

    private var advancedDeviatesFromPreset: Bool {
        let p = preset.params
        return customSteps != p.steps
            || abs(customGuidance - Double(p.guidance)) > 0.0001
            || customSize != p.width
    }

    private func syncCustomFromPreset() {
        let p = preset.params
        customSteps = p.steps
        customGuidance = Double(p.guidance)
        customSize = p.width
    }

    private var resolvedParams: FluxGenerationParams {
        // Advanced overrides always win when the user has touched them;
        // otherwise we ship the preset values as-is. The preset row
        // resets advanced state when changed, so this picks up cleanly.
        FluxGenerationParams(
            width: customSize,
            height: customSize,
            steps: customSteps,
            guidance: Float(customGuidance)
        )
    }

    private func startGeneration() {
        guard let entryId = UUID(uuidString: entry.id) else {
            phase = .error("Invalid entry id.")
            return
        }
        let params = resolvedParams
        let layout = preserveLayout
        phase = .generating
        generationTask?.cancel()
        generationTask = Task {
            do {
                let path = try await EntryPipeline.production.generateVariant(
                    entryId: entryId,
                    params: params,
                    preserveLayout: layout
                )
                if Task.isCancelled { return }
                await MainActor.run {
                    variantRefreshToken = UUID()
                    phase = .reviewing(variantPath: path)
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    phase = .error(error.localizedDescription)
                }
            }
        }
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        phase = .configuring
    }

    private func regenerate() {
        // Keep the variant on disk until the next generation overwrites
        // it: the user said "do another," so we don't need to clear
        // this one first. The new file just lands at the same path.
        startGeneration()
    }

    private func discardAndReturn() {
        if case .reviewing(let path) = phase {
            Task { await EntryPipeline.production.discardVariant(variantPath: path) }
        }
        phase = .configuring
    }

    private func acceptAndDismiss() {
        guard case .reviewing(let path) = phase,
              let entryId = UUID(uuidString: entry.id) else { return }
        Task {
            do {
                try await EntryPipeline.production.acceptVariant(
                    entryId: entryId,
                    variantPath: path
                )
                await MainActor.run {
                    onAccepted?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    phase = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Glyph

    private func radioGlyph(isSelected: Bool) -> some View {
        ZStack {
            Circle().stroke(isSelected ? DS.ink : DS.hairline, lineWidth: 1)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle().fill(DS.ink).frame(width: 7, height: 7)
            }
        }
    }
}
