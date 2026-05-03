import SwiftUI

// User-facing editor for the four Flux per-kingdom prompt templates.
// Lives behind the "Illustration style" trigger in the LibraryView sidebar.
// Edits are held in @State and only committed to UserDefaults on Save.

struct IllustrationStyleSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let allKingdoms: [Kingdom] = [.plant, .animal, .fungus, .other]

    @State private var drafts: [Kingdom: String] = [:]
    @State private var errors: [Kingdom: String] = [:]
    @State private var showCloseConfirm = false
    @State private var showResetAllConfirm = false

    private var isDirty: Bool {
        for kingdom in allKingdoms {
            let saved = IllustrationPromptStore.shared.template(for: kingdom)
            if (drafts[kingdom] ?? saved) != saved { return true }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    ForEach(allKingdoms, id: \.self) { kingdom in
                        editor(for: kingdom)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 28)
            }
            .background(DS.paper)
            Hairline()
            footer
        }
        .frame(width: 760, height: 720)
        .background(DS.paper)
        .onAppear { loadDrafts() }
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $showCloseConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Your edits to the illustration prompts will be lost.")
        }
        .confirmationDialog(
            "Reset all four prompts to defaults?",
            isPresented: $showResetAllConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset all", role: .destructive) {
                for kingdom in allKingdoms {
                    drafts[kingdom] = IllustrationPrompts.defaultTemplate(for: kingdom)
                    errors[kingdom] = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Custom edits in this sheet will be replaced with the originals. Nothing is saved until you press Save.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Edit")
            Text("Illustration style")
                .font(DS.serif(28, weight: .regular))
                .foregroundColor(DS.ink)
                .kerning(-0.3)
            Text("Tweak the per-kingdom prompts that Flux uses to draw each plate. Changes apply to new generations only.")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    // MARK: - Per-kingdom editor

    @ViewBuilder
    private func editor(for kingdom: Kingdom) -> some View {
        let draft = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
        let isModified = draft != IllustrationPrompts.defaultTemplate(for: kingdom)
        let rowError = errors[kingdom]

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: kingdom.displayLabel)
                if isModified {
                    MonoLabel(text: "MODIFIED", size: 9.5, color: DS.amber)
                }
                Spacer()
                if isModified {
                    Button("Reset to default") {
                        drafts[kingdom] = IllustrationPrompts.defaultTemplate(for: kingdom)
                        errors[kingdom] = nil
                    }
                    .buttonStyle(GhostButtonStyle())
                }
            }

            TextEditor(text: Binding(
                get: { drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom) },
                set: {
                    drafts[kingdom] = $0
                    if errors[kingdom] != nil { errors[kingdom] = nil }
                }
            ))
            .font(DS.mono(11.5))
            .foregroundColor(DS.ink)
            .scrollContentBackground(.hidden)
            .padding(10)
            .background(DS.paperDeep)
            .overlay(Rectangle().stroke(rowError == nil ? DS.hairline : DS.rust, lineWidth: 1))
            .frame(minHeight: 130)

            HStack(spacing: 8) {
                MonoLabel(text: "VARIABLES")
                Text("{scientific_name} · {common_name} · {subject}")
                    .font(DS.mono(10.5))
                    .foregroundColor(DS.muted)
            }

            if let rowError {
                Text(rowError)
                    .font(DS.sans(11))
                    .foregroundColor(DS.rust)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Reset all to defaults") { showResetAllConfirm = true }
                .buttonStyle(GhostButtonStyle())

            Spacer()

            Button("Cancel") {
                if isDirty { showCloseConfirm = true } else { dismiss() }
            }
            .buttonStyle(QuietButtonStyle())

            Button("Save") { save() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 18)
        .background(DS.paper)
    }

    // MARK: - Logic

    private func loadDrafts() {
        for kingdom in allKingdoms {
            drafts[kingdom] = IllustrationPromptStore.shared.template(for: kingdom)
        }
    }

    private func save() {
        // Validate every draft. Block save if any has unknown placeholders;
        // surface the offenders in each row's inline error.
        var nextErrors: [Kingdom: String] = [:]
        for kingdom in allKingdoms {
            let draft = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
            let unknown = IllustrationPrompts.unknownPlaceholders(in: draft)
            if !unknown.isEmpty {
                let listed = unknown.sorted().map { "{\($0)}" }.joined(separator: ", ")
                nextErrors[kingdom] = "Unknown variable\(unknown.count > 1 ? "s" : "") \(listed). Allowed: {scientific_name}, {common_name}, {subject}."
            }
        }
        errors = nextErrors
        if !nextErrors.isEmpty { return }

        var toPersist: [Kingdom: String] = [:]
        for kingdom in allKingdoms {
            toPersist[kingdom] = drafts[kingdom] ?? IllustrationPromptStore.shared.template(for: kingdom)
        }
        IllustrationPromptStore.shared.setOverrides(toPersist)
        dismiss()
    }
}
