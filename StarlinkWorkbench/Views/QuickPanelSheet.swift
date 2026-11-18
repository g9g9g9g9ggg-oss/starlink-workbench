import SwiftUI

// MARK: - 快捷面板（文本插入/直发 + 图片直发，对齐网页 QuickPanel）

struct QuickPanelSheet: View {
    @ObservedObject var store: WorkbenchStore
    @Binding var texts: [WBQuickText]
    @Binding var images: [WBQuickImage]
    @Binding var search: String
    let onPickText: (String) -> Void
    let onSendText: (String) -> Void
    let onSendImage: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0 // 0=文本 1=图片

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    segButton("文本 \(filteredTexts.count)", idx: 0)
                    segButton("图片 \(filteredImages.count)", idx: 1)
                }
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(Color.wxTertiaryText)
                    TextField("搜索", text: $search)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Color.wxCell)
                .cornerRadius(Strat.corner)
                .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                    .strokeBorder(Color.inkLine, lineWidth: 1))
                .padding(.horizontal, 16)

                ScrollView {
                    if mode == 0 {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredTexts, id: \.id) { t in
                                quickTextRow(t)
                            }
                            if filteredTexts.isEmpty {
                                Text("暂无快捷文本")
                                    .font(.footnote)
                                    .foregroundColor(Color.wxTertiaryText)
                                    .padding(.top, 40)
                            }
                        }
                        .padding(16)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                                  spacing: 10) {
                            ForEach(filteredImages, id: \.id) { img in
                                Button {
                                    onSendImage(img.fileId)
                                    dismiss()
                                } label: {
                                    RemoteImage(urlString: store.base + img.url, size: nil)
                                        .frame(height: 104)
                                }
                                .buttonStyle(.plain)
                            }
                            if filteredImages.isEmpty {
                                Text("暂无快捷图片")
                                    .font(.footnote)
                                    .foregroundColor(Color.wxTertiaryText)
                                    .padding(.top, 40)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.wxBackground.ignoresSafeArea())
            .navigationTitle("快捷素材")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var filteredTexts: [WBQuickText] {
        guard !search.isEmpty else { return texts }
        let q = search.lowercased()
        return texts.filter {
            $0.title.lowercased().contains(q) || $0.content.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    private var filteredImages: [WBQuickImage] {
        guard !search.isEmpty else { return images }
        let q = search.lowercased()
        return images.filter {
            $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private func segButton(_ title: String, idx: Int) -> some View {
        let active = mode == idx
        Button {
            mode = idx
        } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .semibold : .regular))
                .foregroundColor(active ? Color.wxText : Color.wxSecondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(active ? Color.wxBackground : Color.clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func quickTextRow(_ t: WBQuickText) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if !t.category.isEmpty {
                    Text(t.category)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                            .strokeBorder(Color.accent.opacity(0.5), lineWidth: 1))
                }
                Text(t.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.wxText)
                Spacer()
            }
            Text(t.content)
                .font(.system(size: 12))
                .foregroundColor(Color.wxSecondaryText)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button {
                    onPickText(t.content)
                    dismiss()
                } label: {
                    Text("插入")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.wxText)
                        .frame(width: 64, height: 30)
                        .background(Color.wxBackground)
                        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
                            .strokeBorder(Color.inkLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button {
                    onSendText(t.content)
                    dismiss()
                } label: {
                    Text("发送")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 30)
                        .background(RoundedRectangle(cornerRadius: Strat.corner).fill(Color.accent))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(10)
        .background(Color.wxCell)
        .cornerRadius(Strat.corner)
        .overlay(RoundedRectangle(cornerRadius: Strat.corner)
            .strokeBorder(Color.inkLine, lineWidth: 1))
    }
}
