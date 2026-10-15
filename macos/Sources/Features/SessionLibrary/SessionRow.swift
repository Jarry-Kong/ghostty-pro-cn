import SwiftUI

/// 历史会话列表中的一行。
struct SessionRow: View {
    @Binding var record: SessionRecord
    var onOpen: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.isPinned ? "pin.fill" : "terminal")
                .foregroundStyle(record.isPinned ? .orange : .secondary)

            VStack(alignment: .leading, spacing: 3) {
                TextField("会话名称", text: $record.title)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { record.updatedAt = .now }
                if let directory = record.directory, !directory.isEmpty {
                    Text(directory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)
            Toggle("置顶", isOn: $record.isPinned)
                .toggleStyle(.checkbox)

            Text(record.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("打开", action: { onOpen?() })
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
    }
}
