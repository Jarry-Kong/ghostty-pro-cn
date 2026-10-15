import AppKit
import SwiftUI

struct SessionLibraryView: View {
    @ObservedObject var model: SessionLibraryModel
    var onOpen: ([ClaudeSessionRecord], ClaudeSessionOpenMode) -> Void
    var onClose: () -> Void
    @State private var editingID: String?
    @State private var editedTitle = ""
    // 使用恢复版独立设置域，原包首次默认模式仍待取证。
    @AppStorage("sessionLibrary.openMode") private var mode = ClaudeSessionOpenMode.separateWindows
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("按名字、目录或说过的话搜", text: $model.keyword)
                if !model.keyword.isEmpty {
                    Button { model.keyword = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).help("清空搜索")
                }
                Picker("筛选", selection: $model.filter) {
                    ForEach(SessionLibraryModel.Filter.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).frame(width: 230)
                Button("全选") { model.selectAllVisible() }.disabled(model.visibleRecords.isEmpty)
                Button("清空") { model.selection.removeAll() }.disabled(model.selection.isEmpty)
                Button { Task { await model.reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新扫描历史会话").disabled(model.isLoading)
            }.padding()
            Divider()
            if model.isLoading { ProgressView("正在扫描历史会话…").padding() }
            if let error = model.errorMessage { Text(error).foregroundColor(.red).padding() }
            if model.visibleRecords.isEmpty && !model.isLoading {
                VStack(spacing: 10) {
                    Text(model.keyword.isEmpty && model.filter == .all ? "没有找到任何历史会话" : "没有匹配的会话")
                    if model.keyword.isEmpty && model.filter == .all {
                        Text("会话记录在 ~/.claude/projects 下，用过 Claude Code 之后才会有")
                    } else {
                        Button("清掉筛选条件") { model.keyword = ""; model.filter = .all }
                    }
                }.foregroundColor(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(model.groupedRecords, id: \.title) { group in
                        Section {
                            ForEach(group.items) { record in
                                sessionRow(record)
                            }
                        } header: {
                            HStack { Text(group.title); Spacer(); Text("\(group.items.count)") }
                        }
                    }
                }.listStyle(.inset)
            }
            Divider()
            HStack {
                Text("勾选要打开的会话（绿点那几个已经开着了，点它会切过去）")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("关闭", action: onClose)
                Button("打开这 \(model.selection.count) 个") { onOpen(model.selectedRecords, mode) }
                    .disabled(model.selection.isEmpty || model.isLoading ||
                        (mode == .splitsInNewWindow && model.selection.count > ClaudeSessionOpenMode.maximumSplits))
            }.padding()
            HStack {
                Text("打开方式")
                Picker("打开方式", selection: $mode) {
                    ForEach(ClaudeSessionOpenMode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().pickerStyle(.radioGroup)
                Spacer()
            }.padding([.horizontal, .bottom])
            if mode == .splitsInNewWindow && model.selection.count > ClaudeSessionOpenMode.maximumSplits {
                Text("分成列最多 5 个，请减少选择或换成标签页方式")
                    .font(.caption).foregroundColor(.secondary).padding(.bottom)
            }
        }
        .frame(minWidth: 780, minHeight: 440)
        .task { await model.reload() }
    }

    private func sessionRow(_ record: ClaudeSessionRecord) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.selection.contains(record.id) },
                set: { checked in
                    if checked { model.selection.insert(record.id) } else { model.selection.remove(record.id) }
                }
            )).labelsHidden().toggleStyle(.checkbox).disabled(record.isRunning || record.runningStateUnknown)
            if record.isRunning {
                Circle().fill(Color.green).frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if editingID == record.id {
                        TextField("给这个会话起个名字", text: $editedTitle)
                            .onSubmit { saveRename(record) }
                        Button("保存") { saveRename(record) }
                            .disabled(model.isRenaming || model.isLoading)
                            .help("修改名称侧文件并备份已有名称，不修改对话正文")
                        Button("取消") { editingID = nil }.disabled(model.isRenaming)
                    } else {
                        Text(record.displayName).lineLimit(1)
                    }
                    Spacer()
                    Text(dateText(record.lastActivity)).font(.caption).foregroundColor(.secondary)
                }
                HStack {
                    Text((record.workingDirectory as NSString).abbreviatingWithTildeInPath)
                    if !record.preview.isEmpty { Text("“\(record.preview)”").lineLimit(1) }
                }.font(.caption).foregroundColor(.secondary)
                if record.runningStateUnknown {
                    Text("运行状态待确认，暂不重复打开").font(.caption).foregroundColor(.secondary)
                }
                if record.name?.contains("\u{FFFD}") == true {
                    Text("这个名字里有编码损坏的字符，坏掉的字节已经找不回来了。点右边的「改名」输入正确的名字即可修好")
                        .font(.caption).foregroundColor(.orange)
                }
            }
            if record.isRunning { Button("切到这个会话") { onOpen([record], mode) } }
            Button("改名") { promptRename(record) }
                .disabled(model.isLoading || model.isRenaming)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("改名…") { promptRename(record) }.disabled(model.isLoading || model.isRenaming)
            Button("打开这个会话") { onOpen([record], mode) }
            Button("拷贝恢复命令") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.resumeCommand, forType: .string)
            }.disabled(!record.isValidResumeID)
            Button("拷贝会话编号") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.id, forType: .string)
            }
        }
    }

    private func promptRename(_ record: ClaudeSessionRecord) {
        editedTitle = record.name ?? ""
        editingID = record.id
    }

    private func saveRename(_ record: ClaudeSessionRecord) {
        let title = editedTitle
        Task {
            if await model.rename(record, to: title) { editingID = nil }
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
