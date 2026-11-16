import SwiftUI

/// Second-hand listings from Vinted and OLX for a typed query, with the
/// price spread on top. Opens already searching for the series' title;
/// refine it ("tom 3") and press Return. A listing opens on its site.
struct MarketSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale

    @State private var query: String
    /// What the results are for; changes only on Return, not per keystroke.
    @State private var submittedQuery: String
    @State private var order: MarketSortOrder = .relevance
    @State private var category: MarketCategory = .comics
    /// Nil shows both sites. Both are always searched, so switching is instant.
    @State private var source: Marketplace?
    @State private var results: [Marketplace: [MarketListing]] = [:]
    @State private var failures: [Marketplace: String] = [:]
    @State private var isLoading = false
    @State private var onlyMatching = true

    private let horizontalPadding: CGFloat = 20

    init(initialQuery: String) {
        let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        _query = State(initialValue: trimmed)
        _submittedQuery = State(initialValue: trimmed)
    }

    var body: some View {
        #if os(macOS)
            content
                .frame(minWidth: 720, minHeight: 640)
                .background {
                    // Invisible: Esc closes the sheet.
                    Button("Zamknij") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
        #else
            NavigationStack {
                content
                    .navigationTitle("Ogłoszenia")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Zamknij") { dismiss() }
                        }
                    }
            }
        #endif
    }

    private var content: some View {
        let shown = shownListings

        return VStack(alignment: .leading, spacing: 14) {
            header
            searchBar
            if let summary = MarketPriceSummary(shown) {
                summaryStrip(summary, currency: shown.first?.currencyCode ?? "PLN")
            }
            failureNotes
            results(shown)
        }
        .padding(.top, 20)
        .background(AppBackgroundView())
        .task(id: "\(submittedQuery)|\(order.rawValue)|\(category.rawValue)") {
            await search()
        }
    }

    // MARK: - What's shown

    private var searchedSources: [Marketplace] {
        source.map { [$0] } ?? Marketplace.allCases
    }

    /// The selected sites' listings, merged: by price when sorting by
    /// price, otherwise alternating so each site's own order is kept.
    /// Optionally only those naming what was searched for.
    private var shownListings: [MarketListing] {
        let lists = searchedSources.map { results[$0] ?? [] }
        var merged: [MarketListing]
        if order == .priceLowToHigh {
            merged = lists.joined().sorted { $0.price < $1.price }
        } else {
            merged = []
            for index in 0 ..< (lists.map(\.count).max() ?? 0) {
                merged += lists.compactMap { index < $0.count ? $0[index] : nil }
            }
        }
        return onlyMatching ? merged.filter { $0.matches(submittedQuery) } : merged
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                #if os(macOS)
                    Text("Ogłoszenia")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                #endif
                Text("Vinted i OLX, ok. 100 pierwszych wyników z każdego")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            #if os(macOS)
                SubtleButton(title: "Zamknij", systemImage: "xmark") { dismiss() }
            #endif
        }
        .padding(.horizontal, horizontalPadding)
    }

    /// The controls go under the field, which would otherwise be squeezed
    /// to nothing; on a phone over two rows.
    @ViewBuilder
    private var searchBar: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: 10) {
                searchField
                HStack(spacing: 12) {
                    sourcePicker
                        .fixedSize()
                    categoryPicker
                    sortPicker
                    Spacer(minLength: 0)
                    matchingToggle
                }
            }
            .padding(.horizontal, horizontalPadding)
        #else
            VStack(alignment: .leading, spacing: 10) {
                searchField
                sourcePicker
                HStack {
                    categoryPicker
                    Spacer(minLength: 0)
                    sortPicker
                }
                Toggle("Tylko pasujące", isOn: $onlyMatching)
            }
            .padding(.horizontal, horizontalPadding)
        #endif
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tytuł, np. Berserk tom 3", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }
                .submitLabel(.search)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var sourcePicker: some View {
        Picker("Serwis", selection: $source) {
            Text("Wszystkie").tag(Marketplace?.none)
            ForEach(Marketplace.allCases) { marketplace in
                Text(marketplace.displayName).tag(Marketplace?.some(marketplace))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var categoryPicker: some View {
        Picker("Kategoria", selection: $category) {
            Text("Manga i komiksy").tag(MarketCategory.comics)
            Text("Książki").tag(MarketCategory.books)
            Text("Wszystkie kategorie").tag(MarketCategory.all)
        }
        .labelsHidden()
        .fixedSize()
    }

    private var sortPicker: some View {
        Picker("Sortowanie", selection: $order) {
            Text("Trafność").tag(MarketSortOrder.relevance)
            Text("Najtańsze").tag(MarketSortOrder.priceLowToHigh)
            Text("Najnowsze").tag(MarketSortOrder.newestFirst)
        }
        .labelsHidden()
        .fixedSize()
    }

    private var matchingToggle: some View {
        Toggle("Tylko pasujące", isOn: $onlyMatching)
            .fixedSize()
            .help("Ukrywa ogłoszenia, w których tytule brakuje któregoś z wpisanych słów")
    }

    // MARK: - Summary

    private func summaryStrip(_ summary: MarketPriceSummary, currency: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                StatCardView(title: "ogłoszeń", value: "\(summary.count)", systemImage: "tag.fill", accentColor: .teal)
                StatCardView(title: "najtaniej", value: amount(summary.lowest), systemImage: "arrow.down", accentColor: .green, unit: currency)
                StatCardView(title: "mediana", value: amount(summary.median), systemImage: "equal", accentColor: .blue, unit: currency)
                StatCardView(title: "najdrożej", value: amount(summary.highest), systemImage: "arrow.up", accentColor: .orange, unit: currency)
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    // MARK: - Results

    /// A site that failed while the other answered: said once, above the
    /// list, instead of replacing it.
    @ViewBuilder
    private var failureNotes: some View {
        let failed = searchedSources.filter { failures[$0] != nil }
        if !failed.isEmpty, failed.count < searchedSources.count {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(failed) { marketplace in
                    Label(failures[marketplace] ?? "", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private func results(_ shown: [MarketListing]) -> some View {
        let failed = searchedSources.compactMap { failures[$0] }
        if !failed.isEmpty, failed.count == searchedSources.count {
            message(failed.joined(separator: "\n"), systemImage: "exclamationmark.triangle")
        } else if shown.isEmpty, !isLoading {
            message(
                submittedQuery.isEmpty ? L("Wpisz tytuł i naciśnij Return.") : L("Brak ogłoszeń dla „%@”.", submittedQuery),
                systemImage: "magnifyingglass"
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(shown) { listing in
                        Button {
                            openURL(listing.url)
                        } label: {
                            row(listing)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, 20)
            }
            .opacity(isLoading ? 0.5 : 1)
        }
    }

    private func row(_ listing: MarketListing) -> some View {
        HStack(spacing: 12) {
            // OLX photos are often landscape; cropped to the cover's shape.
            CoverImageView(url: listing.thumbnailURL, cornerRadius: 6, maxPixelSize: 240)
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(listing.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    sourceBadge(listing.source)
                        .fixedSize()
                    if let condition = listing.condition {
                        Text(condition)
                    }
                    if let location = listing.location {
                        Label(location, systemImage: "mappin")
                            .lineLimit(1)
                    }
                    if listing.favouriteCount > 0 {
                        Label("\(listing.favouriteCount)", systemImage: "heart")
                    }
                }
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(price(listing.price, listing.currencyCode))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let total = listing.totalPrice {
                    Text("\(price(total, listing.currencyCode)) z ochroną")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if listing.isNegotiable {
                    Text("do negocjacji")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func sourceBadge(_ marketplace: Marketplace) -> some View {
        let tint: Color = marketplace == .vinted ? .teal : .purple
        return Text(marketplace.displayName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(horizontalPadding)
    }

    // MARK: - Loading

    /// Both sites at once; each one's results or error is kept on its own,
    /// so one being down doesn't hide the other.
    private func search() async {
        guard !submittedQuery.isEmpty else {
            results = [:]
            failures = [:]
            return
        }
        isLoading = true
        defer { isLoading = false }

        let query = submittedQuery
        let order = order
        let category = category
        let outcomes = await withTaskGroup(of: (Marketplace, Result<[MarketListing], Error>).self) { group in
            for marketplace in Marketplace.allCases {
                group.addTask {
                    do {
                        return try await (marketplace, .success(marketplace.search(query, order: order, category: category)))
                    } catch {
                        return (marketplace, .failure(error))
                    }
                }
            }
            return await group.reduce(into: [(Marketplace, Result<[MarketListing], Error>)]()) { $0.append($1) }
        }
        // A newer search replaced this one.
        guard !Task.isCancelled else { return }

        var newResults: [Marketplace: [MarketListing]] = [:]
        var newFailures: [Marketplace: String] = [:]
        for (marketplace, outcome) in outcomes {
            switch outcome {
            case let .success(listings):
                newResults[marketplace] = listings
            case let .failure(error):
                newFailures[marketplace] = "\(marketplace.displayName): \(error.localizedDescription)"
            }
        }
        results = newResults
        failures = newFailures
    }

    // MARK: - Formatting

    private func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    private func price(_ value: Double, _ currencyCode: String) -> String {
        value.formatted(.currency(code: currencyCode).locale(locale))
    }
}
