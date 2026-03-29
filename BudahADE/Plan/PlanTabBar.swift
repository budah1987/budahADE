import SwiftUI

// MARK: - Plan Tab Bar

struct PlanTabBar: View {
    @Binding var selectedTabID: UUID
    let tabs: [PlanTabInfo]
    let onSelectTab: (UUID) -> Void
    let onCloseTab: (UUID) -> Void
    let onNewTab: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(tabs) { tab in
                    ConversationTab(
                        title: tab.title,
                        isSelected: tab.id == selectedTabID,
                        agentState: tab.agentState,
                        onSelect: { onSelectTab(tab.id) },
                        onClose: { onCloseTab(tab.id) }
                    )
                }

                Spacer(minLength: 0)

                NewAgentTabButton(action: onNewTab)
                    .padding(.trailing, 8)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .background(GlassBackground())

            Rectangle()
                .fill(Theme.borderSubtle)
                .frame(height: 0.5)
        }
    }
}
