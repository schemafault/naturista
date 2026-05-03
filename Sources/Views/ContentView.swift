import SwiftUI
import AppKit

enum NavRoute: Equatable {
    case library
    case detail(Entry)
    case importFlow

    static func == (lhs: NavRoute, rhs: NavRoute) -> Bool {
        switch (lhs, rhs) {
        case (.library, .library), (.importFlow, .importFlow): return true
        case let (.detail(a), .detail(b)): return a.id == b.id
        default: return false
        }
    }
}

struct ContentView: View {
    @State private var route: NavRoute = .library
    @State private var libraryReloadToken = UUID()

    var body: some View {
        ZStack {
            DS.paper.ignoresSafeArea()

            Group {
                switch route {
                case .library:
                    LibraryView(
                        reloadToken: libraryReloadToken,
                        onOpen: { route = .detail($0) },
                        onImport: { route = .importFlow }
                    )
                case .detail(let entry):
                    EntryDetailView(
                        entry: entry,
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
    }
}
