import SwiftUI

// First-run onboarding screen. Hero-left / panel-right split. The right
// panel switches between idle, downloading, warmup, and warmupFailed
// states based on OnboardingState.phase. Window is locked at 1280x820
// while this is mounted (handled in AppDelegate).
struct OnboardingView: View {
    @ObservedObject var state: OnboardingState
    @State private var quitConfirmPresented = false

    var body: some View {
        GeometryReader { geo in
            // Right panel takes a fixed share of the window so the cards
            // never overflow into the hero or the window edge. Hero takes
            // whatever's left and is clipped by the hero view itself.
            let panelWidth: CGFloat = max(560, min(720, geo.size.width * 0.55))
            let heroWidth: CGFloat = max(0, geo.size.width - panelWidth)
            HStack(spacing: 0) {
                OnboardingHero()
                    .frame(width: heroWidth, height: geo.size.height)
                    .background(DS.paperDeep)
                    .clipped()

                ScrollView {
                    panel
                        .padding(.leading, 44)
                        .padding(.trailing, 56)
                        .padding(.vertical, 44)
                        .frame(width: panelWidth, alignment: .leading)
                }
                .frame(width: panelWidth, height: geo.size.height)
                .background(DS.paper)
            }
        }
        .background(DS.paper)
        .confirmModal(
            isPresented: $quitConfirmPresented,
            title: "Cancel download?",
            message: "The setup is part way through. You can resume it the next time you open Naturista.",
            confirmLabel: "Quit",
            cancelLabel: "Keep downloading",
            isDestructive: true
        ) {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: .onboardingShouldShowQuitConfirm,
                object: nil,
                queue: .main
            ) { _ in
                quitConfirmPresented = true
            }
            NotificationCenter.default.addObserver(
                forName: .onboardingQuitConfirmDismissed,
                object: nil,
                queue: .main
            ) { _ in
                if !quitConfirmPresented {
                    NSApp.reply(toApplicationShouldTerminate: false)
                }
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 24) {
            WordmarkLogo()

            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "First run")
                Text("Welcome.")
                    .font(DS.serif(40, weight: .regular))
                    .foregroundColor(DS.ink)
                    .kerning(-0.5)
                Text("Naturista identifies your finds and illustrates them on this Mac. Two models will download once, then your studio is ready.")
                    .font(DS.sans(13))
                    .foregroundColor(DS.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch state.phase {
            case .idle:
                idlePanel
            case .downloading:
                downloadingPanel
            case .warmup:
                warmupPanel
            case .warmupFailed(let reason):
                warmupFailedPanel(reason: reason)
            case .ready:
                EmptyView()
            }
        }
    }

    // MARK: - Idle (pre-download)

    @ViewBuilder
    private var idlePanel: some View {
        recommendationCard
        whyDisclosure
        primaryButton
    }

    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Recommended for this Mac")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.selectedGemma.displayName)
                        .font(DS.serif(20, weight: .regular))
                        .foregroundColor(DS.ink)
                    Spacer()
                    MonoLabel(
                        text: "~\(formatGB(state.selectedGemma.approxSizeGB))",
                        size: 9.5,
                        color: DS.muted
                    )
                }
                Text(state.selectedGemma.blurb)
                    .font(DS.sans(12))
                    .foregroundColor(DS.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Picked from this Mac's chip and memory. Pick a different size below if you prefer.")
                    .font(DS.sans(11.5))
                    .foregroundColor(DS.muted)
                    .lineSpacing(2)
            }
            .padding(16)

            Hairline()

            disclosureToggle(
                expanded: state.disclosureExpanded,
                label: "Choose a different size"
            ) {
                state.disclosureExpanded.toggle()
            }

            if state.disclosureExpanded {
                Hairline()
                GemmaVariantList(
                    selection: $state.selectedGemma,
                    capability: state.capability,
                    extraDiskHeadroomGB: state.estimatedFluxDiskGB()
                )
                .padding(.horizontal, 0)
            }
        }
        .background(DS.paperDeep)
        .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
    }

    private var whyDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            disclosureToggle(
                expanded: state.whyExpanded,
                label: "Why these models?"
            ) {
                state.whyExpanded.toggle()
            }
            if state.whyExpanded {
                Text("Naturista runs entirely on your Mac. Photos, identifications, and illustrations stay on this device, with nothing sent to a server. The weights come from open-source releases on Hugging Face and live alongside your library.")
                    .font(DS.sans(12))
                    .foregroundColor(DS.inkSoft)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(DS.paperDeep)
        .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
    }

    private var primaryButton: some View {
        let label: String
        let isEnabled: Bool

        if !state.isReachable {
            label = "No internet connection"
            isEnabled = false
        } else if let shortfall = state.diskShortfallGB {
            label = "Needs \(Int(ceil(shortfall))) GB free on this volume"
            isEnabled = false
        } else {
            label = "Download and continue"
            isEnabled = true
        }

        return Button(label) {
            state.startDownloads()
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isEnabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Downloading

    @ViewBuilder
    private var downloadingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(state.selectedGemma.displayName)
                    .font(DS.serif(16, weight: .regular))
                    .foregroundColor(DS.ink)
                MonoLabel(
                    text: "~\(formatGB(state.selectedGemma.approxSizeGB))",
                    size: 9.5,
                    color: DS.muted
                )
                Spacer()
            }
            .padding(14)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))

            if let eta = state.etaText {
                Text(eta)
                    .font(DS.sans(12))
                    .foregroundColor(DS.inkSoft)
            }

            DownloadRowView(
                label: "Illustration model (Flux)",
                row: state.fluxRow,
                onRetry: { state.retry(.flux) }
            )

            DownloadRowView(
                label: "Identification model (\(state.selectedGemma.displayName))",
                row: state.gemmaRow,
                onRetry: { state.retry(.gemma) }
            )
        }

        HStack {
            Spacer()
            if state.isPaused {
                Button("Resume") { state.resume() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Pause") { state.pause() }
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }

    // MARK: - Warmup

    private var warmupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Preparing your studio. This can take a moment on first run.")
                    .font(DS.sans(13))
                    .foregroundColor(DS.inkSoft)
            }
            .padding(14)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
        }
    }

    // MARK: - Warmup failed

    private func warmupFailedPanel(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Warmup failed", color: DS.rust)
                Text("We couldn't load the models. The files are on disk but the pipeline didn't initialize.")
                    .font(DS.sans(13))
                    .foregroundColor(DS.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason)
                    .font(DS.sans(11.5))
                    .foregroundColor(DS.rust)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))

            HStack(spacing: 10) {
                Button("Re-verify downloads") { state.reverifyAndRetryWarmup() }
                    .buttonStyle(QuietButtonStyle())
                Button("Continue anyway") { state.continueAfterWarmupFailure() }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Helpers

    private func disclosureToggle(
        expanded: Bool,
        label: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.muted)
                Text(label)
                    .font(DS.sans(12, weight: .medium))
                    .foregroundColor(DS.ink)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func formatGB(_ gb: Double) -> String {
        gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }
}

// MARK: - DownloadRowView

private struct DownloadRowView: View {
    let label: String
    let row: OnboardingState.RowState
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(DS.sans(12, weight: .medium))
                    .foregroundColor(DS.ink)
                Spacer()
                statusChip
            }

            ProgressBar(percent: percentValue, color: barColor)

            if let sub = subStatus {
                Text(sub)
                    .font(DS.sans(11))
                    .foregroundColor(subStatusColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed = row {
                HStack {
                    Spacer()
                    Button("Retry", action: onRetry)
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .padding(14)
        .background(DS.paperDeep)
        .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
    }

    private var percentValue: Double {
        switch row {
        case .pending: return 0
        case .running(let p, _): return p
        case .paused(let p): return p
        case .failed: return 0
        case .done: return 1
        }
    }

    private var subStatus: String? {
        switch row {
        case .pending: return nil
        case .running(_, let s): return s
        case .paused: return "Paused"
        case .failed(let r): return r
        case .done: return "Installed"
        }
    }

    private var subStatusColor: Color {
        switch row {
        case .failed: return DS.rust
        case .done:   return DS.sage
        case .paused: return DS.amber
        default:      return DS.inkSoft
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        switch row {
        case .pending:
            EmptyView()
        case .running(let p, _):
            MonoLabel(text: "\(Int(p * 100))%", size: 9.5, color: DS.muted)
        case .paused(let p):
            MonoLabel(text: "PAUSED \(Int(p * 100))%", size: 9.5, color: DS.amber)
        case .failed:
            MonoLabel(text: "FAILED", size: 9.5, color: DS.rust)
        case .done:
            MonoLabel(text: "DONE", size: 9.5, color: DS.sage)
        }
    }

    private var barColor: Color {
        switch row {
        case .failed: return DS.rust
        case .done:   return DS.sage
        case .paused: return DS.amber
        default:      return DS.ink
        }
    }
}

private struct ProgressBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DS.paperEdge)
                    .frame(height: 4)
                Rectangle()
                    .fill(color)
                    .frame(width: max(0, min(1, percent)) * geo.size.width, height: 4)
            }
        }
        .frame(height: 4)
    }
}

// Notification names used by AppDelegate to coordinate the cmd-Q
// confirmation dialog. AppDelegate posts the show-modal notification
// from applicationShouldTerminate; the view presents the modal and
// translates the user's choice back into NSApp.reply().
extension Notification.Name {
    static let onboardingShouldShowQuitConfirm = Notification.Name("onboarding.shouldShowQuitConfirm")
    static let onboardingQuitConfirmDismissed  = Notification.Name("onboarding.quitConfirmDismissed")
}
