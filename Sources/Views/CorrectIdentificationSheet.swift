import SwiftUI

// Modal for user-corrected identification. Two free-text fields (common +
// scientific) — fill either; Gemma infers the missing one and re-derives
// family / evidence / confusion-set / FLUX prompt off the corrected
// species. Mirrors the split-out sheet pattern used by
// `IllustrationStyleSheet.swift`.

struct CorrectIdentificationSheet: View {
    @Binding var commonName: String
    @Binding var scientificName: String
    var onCancel: () -> Void
    var onSave: () -> Void
    var onAppearPreload: () -> Void

    private var canSave: Bool {
        !commonName.trimmingCharacters(in: .whitespaces).isEmpty
            || !scientificName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(text: "Correct identification")
            Text("Fill either name. Gemma will infer the other and re-derive family, evidence, and the illustration.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(3)

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Common name", size: 9.5)
                TextField("e.g. Western redbud", text: $commonName)
                    .textFieldStyle(.plain)
                    .font(DS.serif(15))
                    .padding(10)
                    .background(DS.paperDeep)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Scientific name", size: 9.5)
                TextField("e.g. Cercis occidentalis", text: $scientificName)
                    .textFieldStyle(.plain)
                    .font(DS.serif(14, italic: true))
                    .padding(10)
                    .background(DS.paperDeep)
                    .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(GhostButtonStyle())
                Button("Re-run identification", action: onSave)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSave)
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(width: 460)
        .background(DS.paper)
        .onAppear(perform: onAppearPreload)
    }
}
