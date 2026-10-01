import SwiftUI

/// The History tab: the days on the left, the chosen one on the right.
struct HistoryView: View {
    let model: HistoryModel
    @State private var confirming = false

    var body: some View {
        Group {
            if model.entries.isEmpty && !model.loadFailed {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list.frame(width: 320)
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { model.refresh() }
        // The axis of an open day is drawn for the time zone in force when it was built.
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in model.refresh() }
        .confirmationDialog(
            "history.deleteTitle", isPresented: $confirming, titleVisibility: .visible, presenting: model.pendingDelete
        ) { entry in
            Button("history.deleteConfirm", role: .destructive) { model.confirmDelete(entry) }
            Button("history.cancel", role: .cancel) { model.cancelDelete() }
        } message: { _ in
            Text("history.deleteMessage")
        }
        .onChange(of: confirming) { _, isShown in
            // Dismissed some other way (Escape): forget the request.
            if !isShown { model.cancelDelete() }
        }
    }

    // MARK: Parts

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("history.empty").font(.title3.weight(.semibold))
            Text("history.emptyHint").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
                ForEach(model.entries) { entry in
                    HistoryRowView(entry: entry).tag(entry.id)
                }
            }
            if model.loadFailed || model.deleteFailed {
                VStack(alignment: .leading, spacing: 4) {
                    if model.loadFailed { Text("history.loadFailed") }
                    if model.deleteFailed { Text("history.deleteFailed") }
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let overview = model.detail, let entry = model.entries.first(where: { $0.id == model.selection }) {
            HistoryDetailView(model: overview, entry: entry) {
                model.requestDelete(entry.id)
                confirming = model.pendingDelete != nil
            }
        } else {
            Color.clear
        }
    }
}
