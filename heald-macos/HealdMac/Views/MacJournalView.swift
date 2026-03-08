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
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    TextField("Search events...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                }
                .padding(.horizontal, Theme.paddingMD)
                .padding(.vertical, 7)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))

                ForEach(EventCategory.allCases, id: \.self) { category in
                    Button {
                        selectedCategory = selectedCategory == category ? nil : category
                    } label: {
                        Image(systemName: category.icon)
                            .font(.system(size: 11))
                            .frame(width: 28, height: 28)
                            .background(selectedCategory == category ? Theme.accent.opacity(0.15) : Theme.cardBackground)
                            .foregroundStyle(selectedCategory == category ? Theme.accent : Theme.textTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM))
                    }
                    .buttonStyle(.plain)
                    .help(category.label)
                }

                if selectedCategory != nil {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.paddingXL)
            .padding(.vertical, Theme.paddingMD)
            .background(Theme.background)

            Divider().background(Theme.cardBorder)

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
                                    .listRowSeparatorTint(Theme.cardBorder)
                            }
                        } header: {
                            Text(date)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
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
