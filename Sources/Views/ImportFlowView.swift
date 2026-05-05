import SwiftUI
import AppKit

struct ImportFlowView: View {
    var onCancel: () -> Void
    var onCompleted: () -> Void

    enum Stage { case dropzone, preparing, reviewing, identified, composing }

    @State private var stage: Stage = .dropzone
    @State private var importedImage: NSImage?
    @State private var importedURL: URL?
    @State private var entry: Entry?
    @State private var identification: IdentificationResult?
    @State private var identificationError: String?
    @State private var pipelineError: String?
    @State private var isCorrecting = false
    @State private var showCorrectionSheet = false
    @State private var correctionDraftCommon = ""
    @State private var correctionDraftScientific = ""
    @State private var preserveLayout = false
    @State private var hintCommon = ""
    @State private var hintScientific = ""
    @State private var hintExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Hairline()
            ScrollView {
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        Stepper(stage: stage)
                            .padding(.bottom, 36)

                        Group {
                            switch stage {
                            case .dropzone: dropzoneStage
                            case .preparing: preparingStage
                            case .reviewing: reviewingStage
                            case .identified: identifiedStage
                            case .composing: composingStage
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: 920, alignment: .topLeading)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 56)
                .padding(.top, 32)
                .padding(.bottom, 56)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.paper)
        .onAppear { NSApp.windows.first?.title = "Naturista: New Entry" }
        .sheet(isPresented: $showCorrectionSheet) {
            CorrectIdentificationSheet(
                commonName: $correctionDraftCommon,
                scientificName: $correctionDraftScientific,
                onCancel: { showCorrectionSheet = false },
                onSave: submitCorrection,
                onAppearPreload: { Task { await GemmaActor.shared.preload() } }
            )
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            MonoLabel(text: "NEW ENTRY", color: DS.muted)
            HStack {
                Button(action: onCancel) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .regular))
                        Text("Library")
                    }
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 18)
        .background(DS.paper)
    }

    // MARK: - Stage 1 — Dropzone

    private var dropzoneStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add a specimen")
                .font(DS.serif(26, weight: .regular))
                .foregroundColor(DS.ink)
            Text("A clear, well-lit photograph of a single subject (plant, animal, or fungus) yields the strongest identification.")
                .font(DS.sans(13))
                .lineSpacing(3)
                .foregroundColor(DS.inkSoft)
                .frame(maxWidth: 540, alignment: .leading)
                .padding(.top, 6)

            Dropzone(action: chooseFile)
                .frame(maxHeight: 280)
                .padding(.top, 24)

            HStack(alignment: .top, spacing: 32) {
                hintColumn(numeral: "I", title: "Subject fills the frame", text: "Capture the whole organism with diagnostic features visible.")
                hintColumn(numeral: "II", title: "Even natural light", text: "Avoid harsh shadows and underexposure.")
                hintColumn(numeral: "III", title: "One subject at a time", text: "A single specimen yields the cleanest plate.")
            }
            .padding(.top, 28)
        }
    }

    private func hintColumn(numeral: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoLabel(text: numeral, color: DS.muted)
                .padding(.bottom, 2)
            Text(title)
                .font(DS.serif(15))
                .foregroundColor(DS.ink)
            Text(text)
                .font(DS.sans(12.5))
                .foregroundColor(DS.inkSoft)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Stage 2 — Preparing (optional hint)

    private var preparingStage: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ready to identify")
                    .font(DS.serif(26))
                    .foregroundColor(DS.ink)
                Text("If you have a guess for the subject, you can offer it as a hint. The model will treat it as a starting point but may override it if the photograph clearly shows otherwise.")
                    .font(DS.sans(13))
                    .lineSpacing(3)
                    .foregroundColor(DS.inkSoft)
                    .frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 8)

                hintDisclosure
                    .padding(.top, 24)

                if hintExpanded {
                    hintFields
                        .padding(.top, 14)
                }

                HStack(spacing: 10) {
                    Button(action: runIdentification) {
                        Text("Identify")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("Discard", action: discardImport)
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ImportedPhotoCard(image: importedImage)
                .frame(maxWidth: .infinity)
        }
    }

    private var hintDisclosure: some View {
        Button(action: { hintExpanded.toggle() }) {
            HStack(spacing: 8) {
                Image(systemName: hintExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DS.ink)
                Text("Add a hint to guide identification (optional)")
                    .font(DS.sans(12.5, weight: .medium))
                    .tracking(0.24)
                    .foregroundColor(DS.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var hintFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Common name", size: 9.5)
                TextField("e.g. Western redbud", text: $hintCommon)
                    .textFieldStyle(.plain)
                    .font(DS.serif(15))
                    .padding(10)
                    .background(DS.paperDeep)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Scientific name", size: 9.5)
                TextField("e.g. Cercis occidentalis", text: $hintScientific)
                    .textFieldStyle(.plain)
                    .font(DS.serif(14, italic: true))
                    .padding(10)
                    .background(DS.paperDeep)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    // MARK: - Stage 3 — Reviewing

    private var reviewingStage: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Reading the photograph")
                    .font(DS.serif(26))
                    .foregroundColor(DS.ink)
                Text("The local model is examining the photograph for diagnostic features. This typically takes between 20 and 40 seconds.")
                    .font(DS.sans(13))
                    .lineSpacing(3)
                    .foregroundColor(DS.inkSoft)
                    .frame(maxWidth: 440, alignment: .leading)
                    .padding(.top, 8)

                MarchingProgress()
                    .padding(.top, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ImportedPhotoCard(image: importedImage)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Stage 4 — Identified

    private var identifiedStage: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 18) {
                if let id = identification {
                    IdentificationPanelView(result: id)
                } else if let error = identificationError {
                    IdentificationErrorView(message: error)
                } else {
                    IdentificationLoadingView()
                }

                preserveLayoutToggle
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button(action: composePlate) {
                        Text("Compose plate")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(identification == nil || isCorrecting)

                    Button("Discard", action: discardImport)
                        .buttonStyle(QuietButtonStyle())
                        .disabled(isCorrecting)

                    Button(action: startCorrection) {
                        HStack(spacing: 6) {
                            if isCorrecting { ProgressView().controlSize(.small) }
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .regular))
                            Text(isCorrecting ? "Re-identifying…" : "Edit ID")
                        }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(identification == nil || isCorrecting)
                }
                .padding(.top, 8)

                if let error = pipelineError {
                    Text(error)
                        .font(DS.sans(11))
                        .foregroundColor(DS.rust)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                ImportedPhotoCard(image: importedImage)
                if let url = importedURL, let size = imageDimensions(at: url) {
                    Text("\(formattedDate(for: url)) · \(size.0) × \(size.1)")
                        .font(DS.serif(13, italic: true))
                        .foregroundColor(DS.muted)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Preserve-layout toggle

    private var preserveLayoutToggle: some View {
        Button(action: {
            guard identification != nil, !isCorrecting else { return }
            preserveLayout.toggle()
        }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Rectangle()
                        .stroke(preserveLayout ? DS.ink : DS.hairline, lineWidth: 1)
                        .frame(width: 14, height: 14)
                    if preserveLayout {
                        Rectangle()
                            .fill(DS.ink)
                            .frame(width: 7, height: 7)
                    }
                }
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Match photograph composition")
                            .font(DS.sans(13, weight: preserveLayout ? .semibold : .medium))
                            .foregroundColor(DS.ink)
                        MonoLabel(text: "MUCH SLOWER", size: 9, color: DS.amber)
                    }
                    Text("Uses your photograph as a visual reference so the illustration borrows its pose and layout. Generation takes noticeably longer than the default.")
                        .font(DS.sans(11.5))
                        .foregroundColor(DS.inkSoft)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(identification == nil || isCorrecting)
    }

    // MARK: - Stage 5 — Composing plate

    private var composingStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Composing the plate")
                .font(DS.serif(26))
                .foregroundColor(DS.ink)
            Text(preserveLayout
                 ? "Drawing the illustration with your photograph as a visual reference. This takes longer than the default: please leave the window open."
                 : "The illustration is being drawn and arranged within the plate frame.")
                .font(DS.sans(13))
                .foregroundColor(DS.inkSoft)
                .frame(maxWidth: 540, alignment: .leading)
            MarchingProgress(label: "Composing…")
                .padding(.top, 12)
            if let err = pipelineError {
                Text(err)
                    .font(DS.sans(11))
                    .foregroundColor(DS.rust)
                    .lineSpacing(2)
            }
        }
    }

    // MARK: - Side effects

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Import Photo"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        importedURL = url
        importedImage = NSImage(contentsOf: url)
        identificationError = nil
        identification = nil
        pipelineError = nil
        hintCommon = ""
        hintScientific = ""
        hintExpanded = false
        stage = .preparing
    }

    private func runIdentification() {
        guard let url = importedURL else { return }
        let trimmedCommon = hintCommon.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScientific = hintScientific.trimmingCharacters(in: .whitespacesAndNewlines)
        let common: String? = trimmedCommon.isEmpty ? nil : trimmedCommon
        let scientific: String? = trimmedScientific.isEmpty ? nil : trimmedScientific
        stage = .reviewing

        Task {
            do {
                let entry = try await EntryPipeline.production.importPhoto(
                    at: url,
                    hintCommon: common,
                    hintScientific: scientific
                )
                await MainActor.run { self.entry = entry }

                switch entry.identification.status {
                case .ready(let result):
                    await MainActor.run {
                        identification = result
                        stage = .identified
                    }
                case .failed(let message):
                    await MainActor.run {
                        identificationError = message
                        stage = .identified
                    }
                case .pending:
                    await MainActor.run {
                        identificationError = "The model returned no identification."
                        stage = .identified
                    }
                }
            } catch {
                await MainActor.run {
                    identificationError = error.localizedDescription
                    stage = .identified
                }
            }
        }
    }

    private func composePlate() {
        guard let entry = entry, let entryId = UUID(uuidString: entry.id) else { return }
        stage = .composing
        pipelineError = nil
        let useReferencePhoto = preserveLayout
        Task {
            do {
                try await EntryPipeline.production.illustrate(
                    entryId: entryId,
                    preserveLayout: useReferencePhoto
                )
                await MainActor.run { onCompleted() }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                    stage = .identified
                }
            }
        }
    }

    private func startCorrection() {
        correctionDraftCommon = identification?.topCandidate.commonName ?? ""
        correctionDraftScientific = identification?.topCandidate.scientificName ?? ""
        showCorrectionSheet = true
    }

    private func submitCorrection() {
        guard let entry = entry, let entryId = UUID(uuidString: entry.id) else { return }
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
                let result = try await EntryPipeline.production.applyCorrectedIdentification(
                    entryId: entryId,
                    userCommonName: common,
                    userScientificName: scientific
                )
                await MainActor.run {
                    identification = result
                    isCorrecting = false
                }
            } catch {
                await MainActor.run {
                    pipelineError = error.localizedDescription
                    isCorrecting = false
                }
            }
        }
    }

    private func discardImport() {
        guard let entry = entry, let entryId = UUID(uuidString: entry.id) else {
            onCancel()
            return
        }
        Task {
            try? await EntryPipeline.production.delete(entryId: entryId)
            await MainActor.run { onCancel() }
        }
    }

    private func imageDimensions(at url: URL) -> (Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    private func formattedDate(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = (attrs?[.creationDate] as? Date) ?? Date()
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy"
        return "Captured \(f.string(from: date))"
    }
}

// MARK: - Stepper

private struct Stepper: View {
    let stage: ImportFlowView.Stage

    private struct Step { let id: ImportFlowView.Stage; let label: String }
    private var steps: [Step] {
        [
            Step(id: .dropzone, label: "Photograph"),
            Step(id: .reviewing, label: "Identify"),
            Step(id: .identified, label: "Compose plate"),
        ]
    }

    private func index(for s: ImportFlowView.Stage) -> Int {
        switch s {
        case .dropzone, .preparing: return 0
        case .reviewing: return 1
        case .identified, .composing: return 2
        }
    }

    var body: some View {
        let current = index(for: stage)
        HStack(spacing: 14) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(spacing: 10) {
                    Text(String(format: "%02d", i + 1))
                        .font(DS.mono(9.5))
                        .tracking(0.4)
                        .foregroundColor(i <= current ? DS.ink : DS.muted)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle().stroke(i <= current ? DS.ink : DS.hairline, lineWidth: 1)
                        )
                    Text(step.label)
                        .font(DS.sans(12.5))
                        .tracking(0.24)
                        .foregroundColor(i <= current ? DS.ink : DS.muted)
                }
                if i < steps.count - 1 {
                    Rectangle()
                        .fill(DS.hairline)
                        .frame(width: 80, height: 1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Dropzone

private struct Dropzone: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(DS.mutedDeep)
                VStack(spacing: 2) {
                    Text("Drop a photograph here")
                        .font(DS.serif(18))
                        .foregroundColor(DS.ink)
                    Text("or click to choose a file · JPEG · PNG · HEIC")
                        .font(DS.sans(11))
                        .tracking(0.4)
                        .foregroundColor(DS.muted)
                }
                Text("Browse files")
                    .font(DS.sans(12, weight: .medium))
                    .tracking(0.24)
                    .foregroundColor(DS.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }
            .frame(maxWidth: .infinity)
            .padding(80)
            .background(hovered ? DS.paperDeep : DS.paper)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        hovered ? DS.inkSoft : DS.hairline,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .aspectRatio(16.0/7.0, contentMode: .fit)
    }
}

// MARK: - Imported photo card

private struct ImportedPhotoCard: View {
    let image: NSImage?
    var body: some View {
        ZStack {
            DS.paper
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlatePlaceholder(label: "imported photograph")
            }
        }
        .aspectRatio(4.0/5.0, contentMode: .fit)
        .frame(maxWidth: 360)
        .overlay(Rectangle().stroke(DS.hairlineSoft, lineWidth: 1))
    }
}

// MARK: - Marching progress bar (indeterminate hairline)

private struct MarchingProgress: View {
    var label: String? = nil
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(DS.hairline).frame(height: 1)
                    Rectangle()
                        .fill(DS.ink)
                        .frame(width: geo.size.width * 0.32, height: 1)
                        .offset(x: phase * (geo.size.width * 1.32) - geo.size.width * 0.32)
                }
                .clipped()
            }
            .frame(height: 1)

            if let label {
                Text(label)
                    .font(DS.sans(11))
                    .tracking(0.4)
                    .foregroundColor(DS.muted)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
