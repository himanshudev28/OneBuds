import OneBudsCore
import SwiftUI

/// The primary interface, one click from the menu bar: battery, noise control and volume at a
/// glance, with four tiles that slide in a page each for sound, controls, features and tools.
struct PopoverView: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: PopoverPage?
    /// Direction of the last page change, so pages slide in from where they "are".
    @State private var forward = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            PopoverHeader()

            Group {
                if manager.connection.isConnected {
                    ZStack(alignment: .top) {
                        if let page {
                            PopoverPageView(page: page) { open(nil) }
                                .transition(pageTransition)
                        } else {
                            PopoverHome { open($0) }
                                .transition(pageTransition)
                        }
                    }
                    .clipped()
                } else {
                    Module { CompactConnectionStateView() }
                        .transition(.opacity)
                }
            }

            if let error = manager.lastError, manager.connection.isConnected {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            PopoverFooter()
        }
        .padding(Theme.Spacing.m + 2)
        .frame(width: Theme.Size.popoverWidth)
        .animateState(value: manager.connection.isConnected)
        .animateState(value: manager.lastError)
        .onChange(of: manager.connection.isConnected) { _, connected in
            if !connected { page = nil }
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading)
    }

    private func open(_ destination: PopoverPage?) {
        forward = destination != nil
        withAnimation(reduceMotion ? Theme.Motion.reduced : Theme.Motion.page) { page = destination }
    }
}

/// Home page: battery, noise control, volume and the navigation tiles.
struct PopoverHome: View {
    @Environment(DeviceManager.self) private var manager
    @Environment(AppModel.self) private var model
    let open: (PopoverPage) -> Void

    private var battery: BatteryStatus? {
        guard manager.presentation(.battery) != .hidden, let battery = manager.battery, !battery.isEmpty else { return nil }
        return battery
    }

    private var pages: [PopoverPage] { PopoverPage.allCases.filter { $0.isAvailable(manager) } }

    var body: some View {
        VStack(spacing: Theme.Spacing.s + 2) {
            if manager.presentation(.battery) != .hidden {
                Module(padding: Theme.Spacing.m) {
                    if let battery {
                        BatteryRow(battery: battery, wear: manager.wear)
                    } else {
                        BatteryRow(waitingWith: .regular)
                    }
                }
            }

            if manager.presentation(.noiseControl) != .hidden {
                Module(title: "Noise Control", presentation: manager.presentation(.noiseControl)) {
                    NoiseModeSelector(style: .circles)
                }
            }

            if model.systemVolume.isAdjustable {
                Module(padding: Theme.Spacing.s + 2) { VolumeRow() }
            }

            if !pages.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.s + 2), GridItem(.flexible())], spacing: Theme.Spacing.s + 2) {
                    ForEach(pages) { page in
                        PopoverTile(page: page, subtitle: page.subtitle(manager)) { open(page) }
                    }
                }
            }
        }
    }
}

/// A navigation tile: coloured icon, title, and the current state underneath.
struct PopoverTile: View {
    let page: PopoverPage
    let subtitle: String
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.Radius.module, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s + 2) {
                Image(systemName: page.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.Size.tileIcon, height: Theme.Size.tileIcon)
                    .background(page.tint.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(page.title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface(shape, standardFill: isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.quinary))
            .contentShape(shape)
            .focusRing(shape, isFocused: isFocused)
        }
        .buttonStyle(.pressable)
        .focused($isFocused)
        .focusEffectDisabled()
        .onHover { isHovering = $0 }
        .animation(Theme.Motion.hover, value: isHovering)
        .accessibilityLabel(page.title)
        .accessibilityValue(subtitle)
        .accessibilityHint("Opens \(page.title)")
    }
}
