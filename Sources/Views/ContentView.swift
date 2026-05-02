import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selectedTab = 1
    @State private var lastEntry: Entry?
    @State private var importedImage: NSImage?
    @State private var identificationResult: IdentificationResult?
    @State private var identificationError: String?
    @State private var isImporting = false
    @State private var isIdentifying = false

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView(
                importedImage: $importedImage,
                identificationResult: $identificationResult,
                identificationError: $identificationError,
                isImporting: $isImporting,
                isIdentifying: $isIdentifying,
                lastEntry: $lastEntry,
                onGeneratePlate: handleGeneratePlate
            )
            .tabItem {
                Label("Import", systemImage: "photo.on.rectangle")
            }
            .tag(0)

            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "books.vertical")
                }
                .tag(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleGeneratePlate() {
        print("Generate Plate pressed")
    }
}

struct ImportView: View {
    @Binding var importedImage: NSImage?
    @Binding var identificationResult: IdentificationResult?
    @Binding var identificationError: String?
    @Binding var isImporting: Bool
    @Binding var isIdentifying: Bool
    @Binding var lastEntry: Entry?
    var onGeneratePlate: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection

                if importedImage != nil {
                    photoPreviewSection
                    identificationSection
                    generatePlateSection
                } else {
                    importPromptSection
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Naturista")
                .font(.largeTitle)
                .padding(.top, 20)

            Text("A botanical field journal")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var importPromptSection: some View {
        VStack(spacing: 20) {
            Spacer()

            Button(action: importPhoto) {
                Label("Import Photo", systemImage: "photo.on.rectangle")
                    .font(.title2)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)

            if isImporting {
                ProgressView()
                    .padding()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var photoPreviewSection: some View {
        VStack(spacing: 12) {
            if let image = importedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 300)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }

            Button(action: importPhoto) {
                Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(isIdentifying)
        }
    }

    @ViewBuilder
    private var identificationSection: some View {
        if isIdentifying {
            IdentificationLoadingView()
        } else if let error = identificationError {
            IdentificationErrorView(message: error)
        } else if let result = identificationResult, let entry = lastEntry {
            IdentificationPanelView(
                result: result,
                entryStatus: entry.userStatus
            )
        }
    }

    private var generatePlateSection: some View {
        Button(action: onGeneratePlate) {
            Label("Generate Plate", systemImage: "paintpalette")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isIdentifying || identificationResult == nil || identificationError != nil)
    }

    private func importPhoto() {
        isImporting = true
        identificationResult = nil
        identificationError = nil
        lastEntry = nil
        importedImage = nil

        let panel = NSOpenPanel()
        panel.title = "Import Photo"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            isImporting = false
            return
        }

        if let image = NSImage(contentsOf: url) {
            importedImage = image
        }

        isImporting = false
        isIdentifying = true

        Task {
            do {
                let entry = try await PhotoImportService.shared.importPhoto(from: url)

                let decoder = JSONDecoder()
                var result: IdentificationResult?
                var error: String?

                if let data = entry.identificationJson.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let _ = json["error"] {
                    error = json["error"] as? String
                } else if !entry.identificationJson.isEmpty {
                    result = try decoder.decode(IdentificationResult.self, from: Data(entry.identificationJson.utf8))
                }

                await MainActor.run {
                    lastEntry = entry
                    identificationResult = result
                    identificationError = error
                    isIdentifying = false
                }
            } catch {
                await MainActor.run {
                    identificationError = error.localizedDescription
                    isIdentifying = false
                }
            }
        }
    }
}