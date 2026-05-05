import Foundation
import SwiftUI
import Flux2Core

// First-run orchestration. Owns the phase machine, per-row download state,
// pause/resume, retry, ETA averaging, and network monitoring. Drives the
// OnboardingView. Instantiated by AppDelegate when needsOnboarding() fires;
// when phase flips to .ready, AppDelegate swaps the window contents from
// OnboardingView to ContentView.
@MainActor
final class OnboardingState: ObservableObject {

    enum Phase: Equatable {
        case idle
        case downloading
        case warmup
        case warmupFailed(reason: String)
        case ready
    }

    enum Row: String, Equatable, CaseIterable {
        case flux
        case gemma
    }

    enum RowState: Equatable {
        case pending
        case running(percent: Double, subStatus: String)
        case paused(percent: Double)
        case failed(reason: String)
        case done
    }

    // Phase-level state
    @Published var phase: Phase = .idle

    // Per-row state
    @Published var fluxRow: RowState = .pending
    @Published var gemmaRow: RowState = .pending

    // User selections
    @Published var selectedGemma: GemmaModel
    @Published var disclosureExpanded: Bool = false
    @Published var whyExpanded: Bool = false

    // Derived UX
    @Published var etaText: String? = nil

    // Network reachability is exposed via the embedded monitor; we
    // re-publish here for clean SwiftUI binding.
    @Published var isReachable: Bool = true

    // Pause is a single state for both rows (the user pauses everything).
    @Published var isPaused: Bool = false

    let capability: SystemCapability

    private let monitor: NetworkMonitor
    private var monitorObserver: NSObjectProtocol?
    private var monitorCancellable: Task<Void, Never>?

    private var fluxTask: Task<Void, Never>?
    private var gemmaTask: Task<Void, Never>?
    private var etaTimer: Task<Void, Never>?

    private var sampler = ThroughputSampler()

    init(capability: SystemCapability = .current) {
        self.capability = capability
        self.selectedGemma = OnboardingDetector.recommendedGemma(for: capability)
        self.monitor = NetworkMonitor()
        self.isReachable = monitor.isReachable
        observeNetwork()
    }

    private func observeNetwork() {
        // Mirror NetworkMonitor.isReachable into our own published property
        // so views can bind to a single source. Polling-style observation
        // via a ticker is simpler than wiring Combine here for one bool.
        monitorCancellable = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                let next = self.monitor.isReachable
                if next != self.isReachable { self.isReachable = next }
            }
        }
    }

    // MARK: - Disk precheck

    // Total free disk needed for the selected Gemma plus an estimate for
    // Flux. View uses this to disable the primary button + show inline
    // copy when free space is short.
    var diskShortfallGB: Double? {
        let needed = selectedGemma.requirements.minDiskGB + estimatedFluxDiskGB()
        guard let available = capability.availableDiskGB(at: AppPaths.models) else { return nil }
        let shortfall = needed - available
        return shortfall > 0 ? shortfall : nil
    }

    func estimatedFluxDiskGB() -> Double {
        switch FluxQuantizationStore.shared.selected {
        case .auto:
            return capability.physicalMemoryGB >= 48 ? 47 : 30
        case .ultraMinimal: return 30
        case .minimal:      return 47
        case .balanced:     return 55
        }
    }

    // MARK: - Phase transitions / commands

    func startDownloads() {
        guard phase == .idle else { return }
        // Persist the user's pick so the next launch resumes onto the
        // same Gemma if interrupted.
        GemmaModelStore.shared.setSelected(selectedGemma)

        phase = .downloading
        isPaused = false
        fluxRow = .running(percent: 0, subStatus: "Preparing download...")
        gemmaRow = .running(percent: 0, subStatus: "Preparing download...")
        sampler = ThroughputSampler()
        startETATicker()

        // Skip rows that are already complete : opens the "fresh install
        // missing one model" path with no extra UI.
        if FluxActor.areWeightsInstalled() {
            fluxRow = .done
        } else {
            launchFluxTask()
        }
        if selectedGemma.isInstalled {
            gemmaRow = .done
        } else {
            launchGemmaTask()
        }

        Task { await self.advanceIfBothDone() }
    }

    func pause() {
        guard phase == .downloading else { return }
        // Cancel in-flight tasks. Partials persist on disk so resume picks
        // up cleanly. We snapshot each row's current percent into the
        // .paused case so the progress bar doesn't reset visually.
        fluxTask?.cancel()
        gemmaTask?.cancel()
        fluxTask = nil
        gemmaTask = nil
        etaTimer?.cancel()
        etaTimer = nil
        etaText = nil
        isPaused = true
        if case .running(let p, _) = fluxRow { fluxRow = .paused(percent: p) }
        if case .running(let p, _) = gemmaRow { gemmaRow = .paused(percent: p) }
    }

    func resume() {
        guard isPaused, phase == .downloading else { return }
        isPaused = false
        if case .paused(let p) = fluxRow {
            fluxRow = .running(percent: p, subStatus: "Resuming...")
            launchFluxTask()
        }
        if case .paused(let p) = gemmaRow {
            gemmaRow = .running(percent: p, subStatus: "Resuming...")
            launchGemmaTask()
        }
        startETATicker()
        Task { await self.advanceIfBothDone() }
    }

    func retry(_ row: Row) {
        switch row {
        case .flux:
            guard case .failed = fluxRow else { return }
            fluxRow = .running(percent: 0, subStatus: "Retrying...")
            launchFluxTask()
        case .gemma:
            guard case .failed = gemmaRow else { return }
            gemmaRow = .running(percent: 0, subStatus: "Retrying...")
            launchGemmaTask()
        }
        if etaTimer == nil { startETATicker() }
    }

    func reverifyAndRetryWarmup() {
        // User chose "Re-verify downloads" from the warmup-failed state.
        // Drop selected files and run the full flow again.
        Task {
            try? await GemmaModelDownloader.shared.delete(selectedGemma)
            phase = .idle
            fluxRow = .pending
            gemmaRow = .pending
            startDownloads()
        }
    }

    func continueAfterWarmupFailure() {
        // User accepts the risk; let them into the app.
        phase = .ready
    }

    // MARK: - Row tasks

    private func launchFluxTask() {
        fluxTask = Task { [weak self] in
            guard let self else { return }
            let progress: Flux2DownloadProgressCallback = { [weak self] percent, message in
                Task { @MainActor in
                    guard let self else { return }
                    if Task.isCancelled { return }
                    if case .paused = self.fluxRow { return }
                    self.fluxRow = .running(percent: percent, subStatus: message)
                    self.recordSampler()
                }
            }
            do {
                try await FluxActor.shared.downloadWeights(progress: progress)
                if Task.isCancelled { return }
                await MainActor.run {
                    self.fluxRow = .done
                }
                await self.advanceIfBothDone()
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.fluxRow = .failed(reason: error.localizedDescription)
                }
            }
        }
    }

    private func launchGemmaTask() {
        let model = selectedGemma
        gemmaTask = Task { [weak self] in
            guard let self else { return }
            let target = URL(fileURLWithPath: model.localCachePath)
            do {
                try await HuggingFaceDownloader().download(
                    repo: model.hfRepo,
                    into: target,
                    minDiskGB: model.requirements.minDiskGB,
                    progress: { [weak self] done, total in
                        Task { @MainActor in
                            guard let self else { return }
                            if Task.isCancelled { return }
                            if case .paused = self.gemmaRow { return }
                            let pct = total > 0 ? Double(done) / Double(total) : 0
                            let sub = total > 0 ? "Downloaded \(done) of \(total) files" : "Listing files..."
                            self.gemmaRow = .running(percent: pct, subStatus: sub)
                            self.recordSampler()
                        }
                    }
                )
                if Task.isCancelled { return }
                if !model.isInstalled {
                    await MainActor.run {
                        self.gemmaRow = .failed(reason: "Files missing after download. Please retry.")
                    }
                    return
                }
                await MainActor.run {
                    self.gemmaRow = .done
                }
                await self.advanceIfBothDone()
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.gemmaRow = .failed(reason: error.localizedDescription)
                }
            }
        }
    }

    private func advanceIfBothDone() async {
        guard fluxRow == .done && gemmaRow == .done else { return }
        guard phase == .downloading else { return }
        etaTimer?.cancel()
        etaTimer = nil
        etaText = nil
        phase = .warmup
        await runWarmup()
    }

    private func runWarmup() async {
        // Real Gemma preload : loads weights into RAM so the first
        // identification after onboarding is instant. Always runs during
        // onboarding regardless of GemmaPreloadStore.shared.enabled
        // (those are separate concerns : the launch-time preload
        // preference applies to subsequent launches only).
        do {
            try await ModelLease.shared.withExclusive(.identification) {
                await GemmaActor.shared.preload()
            }
        } catch {
            phase = .warmupFailed(reason: error.localizedDescription)
            return
        }
        // For Flux, verify pipeline construction succeeds (cheap : just
        // confirms files are present and parseable). Real weight load
        // happens lazily on first generate; we accept that one-time hit.
        if !FluxActor.areWeightsInstalled() {
            phase = .warmupFailed(reason: "Flux weights are missing after download.")
            return
        }
        phase = .ready
    }

    // MARK: - ETA / sampler

    private func recordSampler() {
        let cumulative = currentCumulativeUnits()
        sampler.record(cumulative: cumulative)
    }

    private func currentCumulativeUnits() -> Double {
        // Treat each row as 0-100 units for combined ETA purposes. Done
        // and paused rows freeze at their last value.
        return percentValue(of: fluxRow) * 100 + percentValue(of: gemmaRow) * 100
    }

    private func percentValue(of state: RowState) -> Double {
        switch state {
        case .pending: return 0
        case .running(let p, _): return p
        case .paused(let p): return p
        case .failed: return 0
        case .done: return 1.0
        }
    }

    private func startETATicker() {
        etaTimer?.cancel()
        etaTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                let cumulative = self.currentCumulativeUnits()
                let remaining = max(0, 200 - cumulative)
                self.etaText = self.sampler.formattedETA(remaining: remaining)
            }
        }
    }

    deinit {
        fluxTask?.cancel()
        gemmaTask?.cancel()
        etaTimer?.cancel()
        monitorCancellable?.cancel()
    }
}

// Has-active-download check used by AppDelegate's applicationShouldTerminate
// hook to decide whether to show the cmd-Q confirmation modal.
extension OnboardingState {
    var hasActiveDownload: Bool {
        if phase != .downloading { return false }
        let busy: (RowState) -> Bool = {
            switch $0 {
            case .running, .paused: return true
            default: return false
            }
        }
        return busy(fluxRow) || busy(gemmaRow)
    }
}
