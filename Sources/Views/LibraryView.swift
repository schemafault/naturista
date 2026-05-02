import SwiftUI

struct LibraryView: View {
    @State private var entries: [Entry] = []
    @State private var isLoading = false
    @State private var selectedEntry: Entry?
    @State private var showDetail = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading entries...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                emptyStateView
            } else {
                gridView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadEntries()
        }
        .sheet(isPresented: $showDetail) {
            if let entry = selectedEntry {
                EntryDetailView(entry: entry)
                    .frame(minWidth: 500, minHeight: 600)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.4))

            Text("Import your first photo to get started")
                .font(.title3)
                .foregroundColor(.secondary)

            Button("Import Photo", action: {})
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridView: some View {
        let columns = [
            GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(entries) { entry in
                    EntryRowView(entry: entry, onRetry: handleRetry)
                        .onTapGesture {
                            selectedEntry = entry
                            showDetail = true
                        }
                }
            }
            .padding()
        }
    }

    private func loadEntries() {
        isLoading = true
        Task {
            do {
                let fetchedEntries = try await DatabaseService.shared.fetchAllEntries()
                await MainActor.run {
                    entries = fetchedEntries
                    updateWindowTitle()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }

private func handleRetry(_ entry: Entry) {
        Task {
            do {
                try await PipelineService.shared.runFullPipeline(entryId: UUID(uuidString: entry.id)!)
                loadEntries()
            } catch {
                print("Retry failed: \(error)")
                loadEntries()
            }
        }
    }

    private func updateWindowTitle() {
        let entryCount = entries.count
        let title = entryCount == 1 ? "Naturista — 1 entry" : "Naturista — \(entryCount) entries"
        NSApp.windows.first?.title = title
    }
}