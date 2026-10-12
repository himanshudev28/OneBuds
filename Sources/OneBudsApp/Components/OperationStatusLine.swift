import OneBudsCore
import SwiftUI

/// Where a change stands. A confirmation shows briefly, then fades; failures stay until the next
/// attempt. Nothing appears before the earbuds have answered, and when there is nothing to say the
/// view has zero height, so place it in a container with no spacing before it.
struct OperationStatusLine: View {
    let status: DeviceManager.OperationStatus
    var topSpacing: CGFloat = Theme.Spacing.s
    @State private var showsConfirmation = false

    private var hasMessage: Bool {
        switch status {
        case .idle, .pending: false
        case .confirmed: showsConfirmation
        case .failed, .timedOut: true
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear.frame(height: 0)
            message
                .padding(.top, hasMessage ? topSpacing : 0)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animateState(value: hasMessage)
        .task(id: status) { await showConfirmationBriefly() }
    }

    @ViewBuilder
    private var message: some View {
        switch status {
        case .idle, .pending:
            EmptyView()
        case .confirmed:
            if showsConfirmation {
                Label("Confirmed by the earbuds", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        case .timedOut:
            Label("No confirmation from the earbuds. The setting may not have changed.", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
    }

    /// Cancelled and restarted whenever the status changes, so it cannot race a newer result.
    private func showConfirmationBriefly() async {
        guard case .confirmed = status else {
            showsConfirmation = false
            return
        }
        showsConfirmation = true
        try? await Task.sleep(for: Theme.Motion.confirmationVisible)
        guard !Task.isCancelled else { return }
        showsConfirmation = false
    }
}
