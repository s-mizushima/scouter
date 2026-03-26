import SwiftUI

struct FeedSettingsView: View {
    @StateObject private var viewModel = FeedSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Add new feed section
                Section("フィードを追加") {
                    TextField("フィード名", text: $viewModel.newFeedName)
                    TextField("URL", text: $viewModel.newFeedURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    Button("追加") {
                        Task { await viewModel.addFeed() }
                    }
                    .disabled(viewModel.newFeedName.isEmpty || viewModel.newFeedURL.isEmpty)
                }

                // Existing feeds section
                Section("登録済みフィード") {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        ForEach(viewModel.feeds) { feed in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feed.name)
                                        .font(.body)
                                    Text(feed.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { feed.isEnabled },
                                    set: { _ in
                                        Task { await viewModel.toggleFeed(feed) }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let feed = viewModel.feeds[index]
                                Task { await viewModel.deleteFeed(feed) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("フィード管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .alert("エラー", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                await viewModel.loadFeeds()
            }
        }
    }
}
