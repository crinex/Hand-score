import SwiftUI

// Model card gallery view
struct ModelCardGalleryView: View {
    @ObservedObject var viewModel: BenchmarkViewModel
    @ObservedObject var hfService: HuggingFaceService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.headline)

            // Bundled models
            if !viewModel.bundledModels.isEmpty {
                ForEach(viewModel.bundledModels, id: \.lastPathComponent) { model in
                    BundledModelCard(
                        url: model,
                        isSelected: viewModel.modelPath == model,
                        onSelect: { viewModel.modelPath = model }
                    )
                }
            }

            // Downloadable models
            ForEach(ModelCatalog.availableModels) { entry in
                let isDownloaded = hfService.isModelDownloaded(entry.id)
                let downloadedPath = hfService.downloadedModelPath(entry.id)
                let state = hfService.downloadStates[entry.id] ?? .idle

                DownloadableModelCard(
                    entry: entry,
                    isDownloaded: isDownloaded,
                    isSelected: downloadedPath != nil && viewModel.modelPath == downloadedPath,
                    downloadState: state,
                    onSelect: {
                        if let path = downloadedPath {
                            viewModel.modelPath = path
                        }
                    },
                    onDownload: {
                        hfService.downloadModel(entry.id)
                    },
                    onCancel: {
                        hfService.cancelDownload(entry.id)
                    },
                    onDelete: {
                        if viewModel.modelPath == downloadedPath {
                            viewModel.modelPath = viewModel.bundledModels.first
                        }
                        hfService.deleteModel(entry.id)
                    }
                )
            }
        }
    }
}

// MARK: - Bundled-model card

private struct BundledModelCard: View {
    let url: URL
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color(.tertiarySystemBackground))
                        .frame(width: 48, height: 48)

                    Image(systemName: "cpu")
                        .font(.title2)
                        .foregroundColor(isSelected ? .blue : .secondary)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(modelName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text("Bundled")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }

                    Text("Model bundled with the app")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var modelName: String {
        if url == Bundle.main.resourceURL {
            let metaPath = url.appendingPathComponent("meta.yaml").path
            if let content = try? String(contentsOfFile: metaPath, encoding: .utf8),
               let nameLine = content.components(separatedBy: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("name:") }) {
                return nameLine.components(separatedBy: "name:").last?.trimmingCharacters(in: .whitespaces) ?? "Bundled Model"
            }
            return "Bundled Model"
        }
        return url.lastPathComponent
    }
}

// MARK: - Downloadable-model card

private struct DownloadableModelCard: View {
    let entry: ModelCatalogEntry
    let isDownloaded: Bool
    let isSelected: Bool
    let downloadState: HuggingFaceService.DownloadState
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(cardColor.opacity(0.15))
                        .frame(width: 48, height: 48)

                    Image(systemName: entry.iconName)
                        .font(.title2)
                        .foregroundColor(cardColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        Text(entry.family)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(familyColor.opacity(0.15))
                            .foregroundColor(familyColor)
                            .cornerRadius(4)
                    }

                    Text(entry.id)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label("ctx \(entry.contextLength)", systemImage: "text.alignleft")
                        Label(HuggingFaceService.formattedSize(entry.estimatedSizeMB), systemImage: "arrow.down.circle")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Status indicator
                statusView
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                if isDownloaded { onSelect() }
            }

            // Download progress bar
            if case .downloading(let progress, let fileName) = downloadState {
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .tint(.blue)

                    Text(fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .confirmationDialog("Delete Model", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete \(entry.displayName)?")
        }
    }

    private var isDownloading: Bool {
        switch downloadState {
        case .fetching, .downloading: return true
        default: return false
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch downloadState {
        case .fetching:
            ProgressView()
                .controlSize(.small)

        case .downloading:
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

        case .failed(let error):
            VStack(spacing: 4) {
                Button(action: onDownload) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                }
                Text("Failed")
                    .font(.caption2)
                    .foregroundColor(.red)
            }

        default:
            if isDownloaded {
                HStack(spacing: 8) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                    } else {
                        Image(systemName: "circle")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    private var cardColor: Color {
        if isSelected { return .blue }
        if isDownloaded { return .primary }
        return .secondary
    }

    private var familyColor: Color {
        switch entry.family {
        case "Gemma": return .purple
        case "Qwen": return .orange
        case "Llama": return .red
        case "Nanbeige": return .green
        case "VibeThinker": return .pink
        default: return .blue
        }
    }
}
