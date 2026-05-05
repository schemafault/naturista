import SwiftUI
import AppKit

// Loads the bundled hero plate (added to the target's Copy Bundle
// Resources phase) and renders it with scaledToFill in whatever frame
// the parent provides. If the asset is missing for any reason, falls
// back to the existing PlatePlaceholder so the screen still composes.
struct OnboardingHero: View {
    var body: some View {
        if let nsImage = Self.loadHeroImage() {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            PlatePlaceholder(label: "Naturista")
        }
    }

    private static func loadHeroImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "onboarding_hero", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
