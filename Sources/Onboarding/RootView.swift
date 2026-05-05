import SwiftUI
import AppKit

// Top-level switch between onboarding and the main library. Lives between
// AppDelegate and ContentView; chosen so the rest of the app doesn't have
// to know that "onboarding" is a thing : if needsOnboarding fires, we
// just don't mount ContentView until phase flips to .ready.
struct RootView: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        Group {
            if state.phase == .ready {
                ContentView()
                    .transition(.opacity)
            } else {
                OnboardingView(state: state)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.phase == .ready)
        .onChange(of: state.phase) { _, new in
            if new == .ready {
                AppDelegate.shared?.unlockWindowResize()
                AppDelegate.shared?.runDeferredLaunchTasks()
            }
        }
    }
}
