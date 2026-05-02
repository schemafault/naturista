import SwiftUI

struct IdentificationPanelView: View {
    let result: IdentificationResult
    let entryStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topCandidateSection

            Divider()

            modelCertaintyBadge

            if !result.alternatives.isEmpty {
                alternativesSection
            }

            if !result.visibleEvidence.isEmpty {
                evidenceSection(title: "Visible Evidence", items: result.visibleEvidence)
            }

            if !result.missingEvidence.isEmpty {
                evidenceSection(title: "Missing Evidence", items: result.missingEvidence)
            }

            safetyNote

            entryStatusBadge
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var topCandidateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.topCandidate.commonName)
                .font(.title)
                .fontWeight(.semibold)

            Text(result.topCandidate.scientificName)
                .font(.title3)
                .italic()
                .foregroundColor(.secondary)

            Text(result.topCandidate.family)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var modelCertaintyBadge: some View {
        HStack(spacing: 8) {
            certaintyPill

            Text("Model certainty — not a measure of accuracy")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var certaintyPill: some View {
        let (color, label) = certaintyStyle
        return Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }

    private var certaintyStyle: (Color, String) {
        switch result.modelConfidence.lowercased() {
        case "high":
            return (.green, "High certainty")
        case "medium":
            return (.yellow, "Medium certainty")
        case "low":
            return (.red, "Low certainty")
        default:
            return (.gray, "Unknown certainty")
        }
    }

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternatives")
                .font(.headline)

            ForEach(Array(result.alternatives.enumerated()), id: \.offset) { _, alternative in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alternative.commonName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(alternative.scientificName)
                            .font(.caption)
                            .italic()
                            .foregroundColor(.secondary)

                        Text(alternative.reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func evidenceSection(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)

                    Text(item)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var safetyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text("Do not consume or handle based only on this identification.")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var entryStatusBadge: some View {
        HStack {
            let (color, label) = statusStyle
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .cornerRadius(8)

            Spacer()
        }
    }

    private var statusStyle: (Color, String) {
        switch entryStatus.lowercased() {
        case "unreviewed":
            return (.gray, "Unreviewed")
        case "failed":
            return (.red, "Failed")
        case "confirmed":
            return (.green, "Confirmed")
        case "rejected":
            return (.red, "Rejected")
        default:
            return (.gray, entryStatus.capitalized)
        }
    }
}

struct IdentificationLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Identifying plant...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Gemma 4 is analyzing the image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct IdentificationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)

            Text("Identification Failed")
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}