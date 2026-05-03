import SwiftUI

private let pageSize = 16

struct LibraryView: View {
    let reloadToken: UUID
    let onOpen: (Entry) -> Void
    let onImport: () -> Void

    @State private var entries: [Entry] = []
    @State private var isLoading = false
    @State private var query = ""
    @State private var page = 0
    @State private var activeFamily: String? = nil

    private var filtered: [Entry] {
        entries.filter { e in
            let id = e.identification
            let family = id.family ?? ""
            if let fam = activeFamily, family != fam { return false }
            if query.isEmpty { return true }
            let q = query.lowercased()
            let common = id.commonName ?? ""
            let scientific = id.scientificName ?? ""
            return common.lowercased().contains(q)
                || scientific.lowercased().contains(q)
                || family.lowercased().contains(q)
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filtered.count) / Double(pageSize))))
    }

    private var visibleEntries: [Entry] {
        let start = page * pageSize
        let end = min(filtered.count, start + pageSize)
        guard start < end else { return [] }
        return Array(filtered[start..<end])
    }

    private var familyCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for e in entries {
            guard let family = e.identification.family, !family.isEmpty else { continue }
            counts[family, default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key < rhs.key
        }.map { ($0.key, $0.value) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
                .background(DS.paper)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(DS.hairlineSoft).frame(width: 1)
                }

            mainColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.paper)
        }
        .background(DS.paper)
        .onAppear { reload() }
        .onChange(of: reloadToken) { _, _ in reload() }
        .onChange(of: query) { _, _ in page = 0 }
        .onChange(of: activeFamily) { _, _ in page = 0 }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            WordmarkLogo()
                .padding(.horizontal, 14)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Collection")
                    .padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 1) {
                    sidebarRow(title: "All entries", count: entries.count, isActive: activeFamily == nil) {
                        activeFamily = nil
                    }
                    sidebarRow(title: "Recent", count: min(12, entries.count), isActive: false) {}
                    sidebarRow(title: "Pinned", count: 0, isActive: false, dim: true) {}
                }
            }

            if !familyCounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Family")
                        .padding(.horizontal, 14)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(familyCounts.prefix(8), id: \.0) { fam, count in
                            sidebarRow(
                                title: fam,
                                count: count,
                                isActive: activeFamily == fam,
                                italic: true
                            ) {
                                activeFamily = (activeFamily == fam) ? nil : fam
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                MonoLabel(text: "v0.1 · LOCAL")
                Text("All identifications run on this device.")
                    .font(DS.sans(11))
                    .tracking(0.4)
                    .foregroundColor(DS.muted)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .padding(.vertical, 32)
        .padding(.leading, 14)
        .padding(.trailing, 4)
    }

    private func sidebarRow(
        title: String,
        count: Int,
        isActive: Bool,
        italic: Bool = false,
        dim: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Group {
                    if italic {
                        Text(title)
                            .font(DS.serif(13.5, italic: true))
                    } else {
                        Text(title)
                            .font(DS.sans(12.5, weight: isActive ? .medium : .regular))
                    }
                }
                .foregroundColor(isActive ? DS.ink : (dim ? DS.muted : DS.inkSoft))
                Spacer()
                Text(String(format: "%02d", count))
                    .font(DS.mono(10))
                    .tracking(0.5)
                    .foregroundColor(DS.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(isActive ? DS.paperDeep : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: activeFamily.map { "Family · \($0)" } ?? "Library")
                    Text(activeFamily ?? "Field journal")
                        .font(DS.serif(38, weight: .regular))
                        .foregroundColor(DS.ink)
                        .kerning(-0.4)
                    HStack(spacing: 4) {
                        Text("\(filtered.count) \(filtered.count == 1 ? "plate" : "plates")")
                        Text("·")
                        Text("\(Set(filtered.compactMap { $0.identification.family }.filter { !$0.isEmpty }).count) families")
                    }
                    .font(DS.sans(11))
                    .tracking(0.4)
                    .foregroundColor(DS.muted)
                }

                Spacer()

                HStack(spacing: 14) {
                    SearchField(query: $query)
                    Button(action: onImport) {
                        HStack(spacing: 7) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 11, weight: .regular))
                            Text("Import photo")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 32)
            .padding(.bottom, 22)
            Hairline()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entries.isEmpty {
            emptyState
        } else if filtered.isEmpty {
            emptyResults
        } else {
            // GeometryReader sits outside the ScrollView so we can size
            // the masonry columns from the available width without
            // clamping the scroll content height.
            GeometryReader { geo in
                let cols = columnCount(for: geo.size.width)
                ScrollView {
                    VStack(spacing: 28) {
                        MasonryGrid(
                            entries: visibleEntries,
                            columnCount: cols,
                            spacing: 28,
                            onOpen: onOpen
                        )
                        if totalPages > 1 {
                            PaginationBar(page: page, total: totalPages) { page = $0 }
                                .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 36)
                    .padding(.bottom, 28)
                }
                .background(DS.paper)
            }
        }
    }

    private func columnCount(for width: CGFloat) -> Int {
        if width >= 1180 { return 4 }
        if width >= 760  { return 3 }
        if width >= 520  { return 2 }
        return 1
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 60)
            Eyebrow(text: "Library")
            Text("Begin a field journal")
                .font(DS.serif(28))
                .foregroundColor(DS.ink)
            Text("Import a photograph and the local model will draft your first plate.")
                .font(DS.sans(13))
                .foregroundColor(DS.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Import photo", action: onImport)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResults: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 80)
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(DS.serif(22))
                .foregroundColor(DS.ink)
            Text("Try a common name or Latin binomial.")
                .font(DS.sans(13))
                .foregroundColor(DS.inkSoft)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading

    private func reload() {
        isLoading = true
        Task {
            do {
                let fetched = try await DatabaseService.shared.fetchAllEntries()
                await MainActor.run {
                    entries = fetched
                    if let fam = activeFamily, !fetched.contains(where: { $0.identification.family == fam }) {
                        activeFamily = nil
                    }
                    if page >= totalPages { page = 0 }
                    isLoading = false
                    updateWindowTitle()
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func updateWindowTitle() {
        let title = "Naturista — Field Journal"
        NSApp.windows.first?.title = title
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(DS.muted)
            TextField("", text: $query, prompt: Text("Search common or Latin name").foregroundColor(DS.muted))
                .textFieldStyle(.plain)
                .focused($focused)
                .font(DS.sans(12.5))
                .foregroundColor(DS.ink)
                .frame(width: 220)
        }
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused ? DS.ink : DS.hairline)
                .frame(height: 1)
        }
    }
}

// MARK: - Masonry

private struct MasonryGrid: View {
    let entries: [Entry]
    let columnCount: Int
    let spacing: CGFloat
    let onOpen: (Entry) -> Void

    var body: some View {
        let buckets = distribute(entries: entries, into: columnCount)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<buckets.count, id: \.self) { i in
                VStack(spacing: 36) {
                    ForEach(buckets[i]) { entry in
                        EntryRowView(entry: entry, aspectRatio: PlateRatio.ratio(for: entry.id))
                            .onTapGesture { onOpen(entry) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // Round-robin distribution. Cheap and stable; gives a near-balanced
    // layout because aspect ratios are bounded (0.78–1.55) and similar
    // across entries on average.
    private func distribute(entries: [Entry], into count: Int) -> [[Entry]] {
        guard count > 0 else { return [entries] }
        var cols = Array(repeating: [Entry](), count: count)
        for (i, e) in entries.enumerated() {
            cols[i % count].append(e)
        }
        return cols
    }
}

// Deterministic per-id aspect ratios so the masonry has organic variety
// without the layout shifting between renders. Bounded so cards never
// get extreme.
enum PlateRatio {
    private static let pool: [CGFloat] = [0.78, 0.92, 1.05, 1.20, 1.35, 1.55]

    static func ratio(for id: String) -> CGFloat {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return pool[Int(hash % UInt64(pool.count))]
    }
}

// MARK: - Pagination

private struct PaginationBar: View {
    let page: Int
    let total: Int
    let onChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 4) {
                pageButton(label: "‹", width: 32, isActive: false, disabled: page == 0) {
                    onChange(page - 1)
                }
                ForEach(0..<total, id: \.self) { p in
                    pageButton(
                        label: String(format: "%02d", p + 1),
                        width: 28,
                        isActive: p == page,
                        disabled: false
                    ) { onChange(p) }
                }
                pageButton(label: "›", width: 32, isActive: false, disabled: page == total - 1) {
                    onChange(page + 1)
                }
            }
            .padding(.top, 24)
        }
    }

    private func pageButton(label: String, width: CGFloat, isActive: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.mono(11, weight: isActive ? .semibold : .regular))
                .tracking(0.4)
                .foregroundColor(isActive ? DS.ink : DS.muted)
                .frame(width: width, height: 28)
                .background(isActive ? DS.paperDeep : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
    }
}
