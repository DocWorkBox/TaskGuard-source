import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Binding var selection: SidebarFilter

    var body: some View {
        List(SidebarFilter.allCases, selection: $selection) { filter in
            Label {
                HStack {
                    Text(filter.title)
                    Spacer()
                    Text("\(count(for: filter))")
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: filter.systemImage)
            }
            .tag(filter)
        }
        .listStyle(.sidebar)
        .navigationTitle("范围")
    }

    private func count(for filter: SidebarFilter) -> Int {
        monitor.groups(for: filter).count
    }
}
