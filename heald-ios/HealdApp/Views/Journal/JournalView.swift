import SwiftUI

struct JournalView: View {
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
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.paddingSM) {
                        FilterChip(label: "All", isSelected: selectedCategory == nil) {
                            selectedCategory = nil
                        }
                        ForEach(EventCategory.allCases, id: \.self) { category in
                            FilterChip(
                                label: category.label,
                                icon: category.icon,
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = selectedCategory == category ? nil : category
                            }
                        }
                    }
                    .padding(.horizontal, Theme.paddingLG)
                    .padding(.vertical, Theme.paddingMD)
                }

                // Event List
                if filteredEvents.isEmpty {
                    Spacer()
                    VStack(spacing: Theme.paddingMD) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
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
                                    EventRow(event: event)
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
            .navigationTitle("Journal")
            .searchable(text: $searchText, prompt: "Search events")
            .refreshable {
                await appState.refresh()
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.accent.opacity(0.15) : Theme.cardBackground)
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.accent.opacity(0.3) : Theme.cardBorder, lineWidth: 0.5)
            )
        }
    }
}
