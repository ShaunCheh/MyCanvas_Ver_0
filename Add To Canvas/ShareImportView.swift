import SwiftUI

struct ShareImportView: View {
    @ObservedObject var viewModel: ShareImportViewModel

    var body: some View {
        NavigationView {
            List {
                Section {
                    Label(
                        viewModel.incomingImageSummary,
                        systemImage: "photo.on.rectangle.angled"
                    )
                    .foregroundStyle(.secondary)
                }

                if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("正在读取分享内容...")
                            Spacer()
                        }
                    }
                } else {
                    Section("目标图板") {
                        ShareImportDestinationRow(
                            title: "新建图板",
                            subtitle: "导入后自动创建一块新的图板",
                            isSelected: viewModel.selectedDestination == .newBoard
                        ) {
                            viewModel.selectedDestination = .newBoard
                        }

                        if viewModel.boardOptions.isEmpty {
                            Text("当前还没有已有图板，可直接导入到新图板。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.boardOptions) { board in
                                ShareImportDestinationRow(
                                    title: board.title,
                                    subtitle: board.updatedAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    ),
                                    isSelected: viewModel.selectedDestination == .existing(board.boardID)
                                ) {
                                    viewModel.selectedDestination = .existing(board.boardID)
                                }
                            }
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("导入到图板")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        viewModel.cancel()
                    }
                    .disabled(viewModel.isImporting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button(action: viewModel.importSelection) {
                        if viewModel.isImporting {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        } else {
                            Text(viewModel.importButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.canImport == false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            viewModel.loadIfNeeded()
        }
    }
}

private struct ShareImportDestinationRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        isSelected ? Color.accentColor : Color.secondary
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
