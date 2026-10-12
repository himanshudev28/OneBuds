import SwiftUI

struct MainSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Earbuds") {
                ForEach(SidebarItem.earbuds) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
            Section("Information") {
                ForEach(SidebarItem.information) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
    }
}
