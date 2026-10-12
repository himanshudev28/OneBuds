import OneBudsCore
import SwiftUI

struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(DeviceManager.self) private var manager

    private var destination: SidebarItem { model.selection ?? .overview }

    var body: some View {
        NavigationSplitView {
            MainSidebar()
        } detail: {
            DetailView(destination: destination)
                .frame(minWidth: Theme.Size.detailMinWidth, minHeight: Theme.Size.detailMinHeight)
                .navigationTitle(destination.title)
                .navigationSubtitle(manager.earbuds?.name ?? "")
                .toolbar { MainToolbar(manager: manager) }
                .windowGlass()
        }
        .onAppear(perform: AppActivationPolicy.enter)
        .onDisappear(perform: AppActivationPolicy.leave)
    }
}
