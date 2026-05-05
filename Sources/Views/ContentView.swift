import SwiftUI
import AppKit

enum NavRoute: Equatable {
    case library
    case detail(Entry, openRegenerate: Bool)
    case importFlow

    static func == (lhs: NavRoute, rhs: NavRoute) -> Bool {
        switch (lhs, rhs) {
        case (.library, .library), (.importFlow, .importFlow): return true
        case let (.detail(a, ar), .detail(b, br)): return a.id == b.id && ar == br
        default: return false
        }
    }
}

struct ContentView: View {
    @State private var route: NavRoute = .library
    @State private var libraryReloadToken = UUID()
    @State private var libraryPage: Int = 0
    @State private var pendingDelete: Entry? = nil
    @State private var pipelineError: String? = nil

    var body: some View {
        ZStack {
            DS.paper.ignoresSafeArea()

            Group {
                switch route {
                case .library:
                    LibraryView(
                        reloadToken: libraryReloadToken,
                        page: $libraryPage,
                        onOpen: { route = .detail($0, openRegenerate: false) },
                        onImport: { route = .importFlow },
                        onRequestRegenerate: regenerateFromLibrary,
                        onRequestDelete: { pendingDelete = $0 }
                    )
                case .detail(let entry, let openRegenerate):
                    EntryDetailView(
                        entry: entry,
                        openRegenerateOnAppear: openRegenerate,
                        onBack: { route = .library },
                        onDeleted: {
                            libraryReloadToken = UUID()
                            route = .library
                        },
                        onUpdated: { _ in libraryReloadToken = UUID() }
                    )
                case .importFlow:
                    ImportFlowView(
                        onCancel: { route = .library },
                        onCompleted: {
                            libraryReloadToken = UUID()
                            route = .library
                        }
                    )
                }
            }
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper)
        .confirmModal(
            item: $pendingDelete,
            title: { _ in "Delete this plate?" },
            message: { _ in "Removes the entry, original photo, working copy, illustration, and plate. This cannot be undone." },
            confirmLabel: "Delete",
            isDestructive: true
        ) { entry in
            confirmDelete(entry)
        }
    }

    // Library's "Regenerate" context-menu action now opens the detail
    // view with the regenerate options modal already up : keeps every
    // regenerate path going through the same variant review flow.
    private func regenerateFromLibrary(_ entry: Entry) {
        route = .detail(entry, openRegenerate: true)
    }

    private func confirmDelete(_ entry: Entry) {
        guard let entryId = UUID(uuidString: entry.id) else { return }
        pendingDelete = nil
        Task {
            do {
                try await EntryPipeline.production.delete(entryId: entryId)
                await MainActor.run { libraryReloadToken = UUID() }
            } catch {
                await MainActor.run { pipelineError = error.localizedDescription }
            }
        }
    }
}
