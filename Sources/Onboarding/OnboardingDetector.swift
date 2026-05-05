import Foundation

// State-based first-run detection. No flag : we look at what's actually on
// disk so the flow self-heals if a user deletes their model directory or
// drags the app to a fresh Mac.
enum OnboardingDetector {
    // True if we should take over the window with onboarding rather than
    // mounting the library. Three triggers (any one is enough):
    //  1) Fresh install: the user has never selected a Gemma. We check the
    //     raw UserDefaults key (not GemmaModelStore.selected, which falls
    //     back to a default value when absent).
    //  2) The selected Gemma's weight files are missing on disk.
    //  3) The Flux transformer + VAE weights for the resolved quantization
    //     are missing on disk.
    static func needsOnboarding() -> Bool {
        if UserDefaults.standard.object(forKey: "gemma.selectedModel") == nil { return true }
        if !GemmaModelStore.shared.selected.isInstalled { return true }
        if !FluxActor.areWeightsInstalled() { return true }
        return false
    }

    // The Gemma we present as "Recommended for this Mac" on the welcome
    // card. Forwarded to GemmaModel.recommended so the rule lives next to
    // the variant table.
    static func recommendedGemma(for capability: SystemCapability = .current) -> GemmaModel {
        GemmaModel.recommended(for: capability)
    }
}
