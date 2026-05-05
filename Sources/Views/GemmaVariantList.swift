import SwiftUI

// Shared variant picker used in both the Illustration Style settings sheet
// and the first-run onboarding screen. The list owns the radios, badges,
// blurbs, and compatibility reasons. Callers compose any trailing per-row
// action (DELETE / DOWNLOAD in settings) via the `trailing` builder; the
// onboarding flow runs its own download orchestration so it passes nothing.
struct GemmaVariantList<Trailing: View>: View {
    @Binding var selection: GemmaModel
    var capability: SystemCapability = .current
    // When > 0, additional GB the caller plans to download alongside Gemma
    // (Flux, on first run). Variants whose Gemma + extra exceeds free disk
    // get a "NEEDS N GB" badge and become disabled.
    var extraDiskHeadroomGB: Double = 0
    var trailing: (GemmaModel) -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            ForEach(GemmaModel.allCases) { option in
                row(option)
                if option != GemmaModel.allCases.last { Hairline() }
            }
        }
        .background(DS.paperDeep)
        .overlay(Rectangle().stroke(DS.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private func row(_ option: GemmaModel) -> some View {
        let installed = option.isInstalled
        let compat = option.compatibility(on: capability)
        let diskShortfall = diskShortfallGB(for: option)
        let isSelectable = compat.isSelectable && diskShortfall == nil
        let isSelected = selection == option

        HStack(spacing: 0) {
            Button(action: {
                guard isSelectable else { return }
                selection = option
            }) {
                GemmaVariantRowContent(
                    option: option,
                    isSelected: isSelected,
                    installed: installed,
                    compat: compat,
                    diskShortfallGB: diskShortfall
                )
            }
            .buttonStyle(.plain)
            .disabled(!isSelectable)

            trailing(option)
        }
        .background(isSelected ? DS.paper : Color.clear)
        .opacity(isSelectable ? 1.0 : 0.55)
    }

    private func diskShortfallGB(for option: GemmaModel) -> Double? {
        guard extraDiskHeadroomGB > 0 || option.requirements.minDiskGB > 0 else { return nil }
        let needed = option.requirements.minDiskGB + extraDiskHeadroomGB
        guard let available = capability.availableDiskGB(at: AppPaths.models) else { return nil }
        let shortfall = needed - available
        return shortfall > 0 ? shortfall : nil
    }
}

extension GemmaVariantList where Trailing == EmptyView {
    init(
        selection: Binding<GemmaModel>,
        capability: SystemCapability = .current,
        extraDiskHeadroomGB: Double = 0
    ) {
        self.init(
            selection: selection,
            capability: capability,
            extraDiskHeadroomGB: extraDiskHeadroomGB,
            trailing: { _ in EmptyView() }
        )
    }
}

// The visual row content: radio + name + badges + blurb + reason. Callers
// wrap this in a Button to make it tappable and add any trailing slot.
struct GemmaVariantRowContent: View {
    let option: GemmaModel
    let isSelected: Bool
    let installed: Bool
    let compat: ModelCompatibility
    var diskShortfallGB: Double? = nil

    var body: some View {
        HStack(spacing: 14) {
            radioGlyph
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(option.displayName)
                        .font(DS.sans(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(DS.ink)
                    if option == .gemma3_12b {
                        MonoLabel(text: "DEFAULT", size: 9, color: DS.muted)
                    }
                    if installed {
                        MonoLabel(text: "INSTALLED", size: 9, color: DS.sage)
                    } else {
                        MonoLabel(text: "~\(formatGB(option.approxSizeGB))", size: 9, color: DS.amber)
                    }
                    if let shortfall = diskShortfallGB {
                        MonoLabel(text: "NEEDS \(Int(ceil(shortfall))) GB", size: 9, color: DS.rust)
                    }
                    compatibilityBadge(compat)
                }
                Text(option.blurb)
                    .font(DS.sans(11.5))
                    .foregroundColor(DS.inkSoft)
                    .lineLimit(2)
                if let reason = compat.reason {
                    Text(reason)
                        .font(DS.sans(11))
                        .foregroundColor(compat.isSelectable ? DS.amber : DS.rust)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.leading, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var radioGlyph: some View {
        ZStack {
            Circle().stroke(isSelected ? DS.ink : DS.hairline, lineWidth: 1)
                .frame(width: 14, height: 14)
            if isSelected {
                Circle().fill(DS.ink).frame(width: 7, height: 7)
            }
        }
    }

    @ViewBuilder
    private func compatibilityBadge(_ compat: ModelCompatibility) -> some View {
        switch compat {
        case .compatible:
            EmptyView()
        case .marginal:
            MonoLabel(text: "MAY BE SLOW", size: 9, color: DS.amber)
        case .incompatible:
            MonoLabel(text: "INCOMPATIBLE", size: 9, color: DS.rust)
        }
    }

    private func formatGB(_ gb: Double) -> String {
        gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }
}
