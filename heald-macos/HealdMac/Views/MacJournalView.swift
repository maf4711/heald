import SwiftUI

struct MacJournalView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedCategory: EventCategory?
    @State private var searchText = ""

    private var filteredEvents: [ActivityEvent] {
        var events = appState.events
        if let category = selectedCategory {
            events = events.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            events = events.filter {
                $0.summary.localizedCaseInsensitiveContains(searchText) ||
                ($0.detail?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        return events
    }

    private var groupedEvents: [(String, [ActivityEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.dateFormatted }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Theme.paddingSM) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Search events...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                .padding(.horizontal, Theme.paddingMD)
                .padding(.vertical, 8)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                        .stroke(Theme.cardBorder, lineWidth: 0.5)
                )

                ForEach(EventCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = selectedCategory == category ? nil : category
                    } label: {
                        Image(systemName: category.icon)
                            .font(.system(size: 11))
                            .frame(width: 30, height: 30)
                            .background(selectedCategory == category ? Theme.accentDim : Theme.cardBackground)
                            .foregroundStyle(selectedCategory == category ? Theme.accent : Theme.textTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous)
                                    .stroke(selectedCategory == category ? Theme.accent.opacity(0.3) : Theme.cardBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(category.label)
                }

                if selectedCategory != nil {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.paddingXL)
            .padding(.vertical, Theme.paddingMD)
            .background(Theme.surfacePrimary)

            Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

            // Event List
            if filteredEvents.isEmpty {
                Spacer()
                VStack(spacing: Theme.paddingMD) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No events found")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(groupedEvents, id: \.0) { date, events in
                        Section {
                            ForEach(events) { event in
                                MacEventRow(event: event)
                                    .listRowBackground(Theme.background)
                                    .listRowSeparatorTint(Theme.cardBorder.opacity(0.5))
                            }
                        } header: {
                            Text(date)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .textCase(.uppercase)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
    }
}
