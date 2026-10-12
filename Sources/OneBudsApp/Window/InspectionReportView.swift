import SwiftUI

/// Scrollable, selectable monospaced report.
struct InspectionReportView: View {
    let text: String

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.s)
        }
        .frame(minHeight: 220, maxHeight: 420)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
