import SwiftUI

// Quiet identification summary used inside the import flow's "identified"
// stage. Mirrors the sidepanel layout in EntryDetailView.
struct IdentificationPanelView: View {
    let result: IdentificationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Top candidate")
                Text(result.topCandidate.commonName)
                    .font(DS.serif(30, weight: .regular))
                    .foregroundColor(DS.ink)
                Text(result.topCandidate.scientificName)
                    .font(DS.serif(17, italic: true))
                    .foregroundColor(DS.inkSoft)

                HStack(spacing: 8) {
                    Text(result.topCandidate.family)
                        .font(DS.serif(13, italic: true))
                        .foregroundColor(DS.mutedDeep)
                    Text("·")
                        .font(DS.sans(11))
                        .foregroundColor(DS.muted)
                    HStack(spacing: 5) {
                        ConfidenceDot(level: result.modelConfidence)
                        Text("\(result.modelConfidence.lowercased()) certainty")
                            .font(DS.sans(11))
                            .foregroundColor(DS.muted)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) { Hairline(color: DS.hairline) }

            if !result.visibleEvidence.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Visible characters")
                    FlowingTags(tags: result.visibleEvidence)
                }
            }

            if !result.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Alternatives")
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(result.alternatives.enumerated()), id: \.offset) { _, alt in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(alt.commonName)
                                    .font(DS.sans(13))
                                    .foregroundColor(DS.ink)
                                Text(alt.scientificName)
                                    .font(DS.serif(12, italic: true))
                                    .foregroundColor(DS.mutedDeep)
                                if !alt.reason.isEmpty {
                                    Text(alt.reason)
                                        .font(DS.sans(11))
                                        .tracking(0.4)
                                        .foregroundColor(DS.muted)
                                        .padding(.top, 2)
                                }
                            }
                            .padding(.bottom, 10)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(DS.hairlineSoft).frame(height: 1)
                            }
                        }
                    }
                }
            }
        }
    }
}

// Quiet loading & error states used in the import flow.
struct IdentificationLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Reading the photograph…")
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
        }
    }
}

struct IdentificationErrorView: View {
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Identification failed", color: DS.rust)
            Text(message)
                .font(DS.sans(12))
                .foregroundColor(DS.inkSoft)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
