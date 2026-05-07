import SwiftUI

struct ResultsListView: View {
    @ObservedObject var viewModel: BenchmarkViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedResult: BenchmarkResult?

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.savedResults) { result in
                    Button {
                        selectedResult = result
                    } label: {
                        resultRow(result)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        viewModel.deleteResult(viewModel.savedResults[index])
                    }
                }
            }
            .navigationTitle("Benchmark Results")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $selectedResult) { result in
                ResultDetailView(result: result)
            }
            .overlay {
                if viewModel.savedResults.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "chart.bar",
                        description: Text("Run a benchmark and the results will appear here.")
                    )
                }
            }
        }
    }

    private func resultRow(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.model.name)
                .font(.headline)

            HStack {
                Text(String(format: "%.1f tok/s", result.performance.decodeTokensPerSec))
                    .foregroundStyle(.blue)
                Text("|")
                    .foregroundStyle(.secondary)
                Text("\(result.performance.totalTokens) tokens")
                Text("|")
                    .foregroundStyle(.secondary)
                Text(String(format: "%.0f ms", result.performance.ttftMs))
                    .foregroundStyle(.orange)
            }
            .font(.subheadline)

            Text(result.timestamp, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
