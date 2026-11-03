import SwiftUI

struct MainSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Earbuds") {
                ForEach(SidebarItem.earbuds) { item in
                    Label { Text(item.title) } icon: { SidebarIcon(item: item) }.tag(item)
                }
            }
            Section("Information") {
                ForEach(SidebarItem.information) { item in
                    Label { Text(item.title) } icon: { SidebarIcon(item: item) }.tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
    }
}
