import Foundation
import SwiftUI

// MARK: - Run Models Demo

struct RunModelsDemo: View {
    @StateObject private var persistence = RunPersistence.shared
    @State private var demoRuns: [Run] = []
    @State private var demoArtifacts: [Artifact] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Run & Artifact Models Demo")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("This demo shows the Run & Artifact models in action")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Demo Controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Demo Controls")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    Button("Create Sample Run") {
                        createSampleRun()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Create Sample Artifact") {
                        createSampleArtifact()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Clear All") {
                        clearAll()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // Statistics
            if !demoRuns.isEmpty || !demoArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Statistics")
                        .font(.headline)
                    
                    let stats = persistence.getRunStatistics()
                    let artifactStats = persistence.getArtifactStatistics()
                    
                    HStack(spacing: 20) {
                        StatCard(title: "Total Runs", value: "\(stats.totalRuns)")
                        StatCard(title: "Active Runs", value: "\(stats.activeRuns)")
                        StatCard(title: "Total Cost", value: stats.totalCostDisplay)
                        StatCard(title: "Artifacts", value: "\(artifactStats.totalArtifacts)")
                    }
                }
            }
            
            Divider()
            
            // Recent Runs
            if !demoRuns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Runs")
                        .font(.headline)
                    
                    ForEach(demoRuns.prefix(5), id: \.id) { run in
                        RunRowView(run: run)
                    }
                }
            }
            
            // Recent Artifacts
            if !demoArtifacts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Artifacts")
                        .font(.headline)
                    
                    ForEach(demoArtifacts.prefix(5), id: \.id) { artifact in
                        ArtifactDemoRowView(artifact: artifact)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            loadDemoData()
        }
    }
    
    // MARK: - Demo Methods
    
    private func createSampleRun() {
        let modelRef = ModelRef(
            provider: "Mock",
            modelID: "demo-model",
            endpoint: "/demo"
        )
        
        let nodeID = UUID()
        let run = persistence.createRun(
            nodeID: nodeID,
            model: modelRef,
            inputParams: .object([
                "prompt": .string("A beautiful sunset over mountains"),
                "size": .object([
                    "width": .number(512),
                    "height": .number(512)
                ])
            ]),
            resolvedInputs: .object([
                "text": .string("A beautiful sunset over mountains")
            ]),
            nodeSchemaVersion: 1,
            nodeArgsSnapshot: .object([
                "prompt": .string("A beautiful sunset over mountains")
            ])
        )
        
        // Simulate run completion after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            var completedRun = run
            completedRun.status = .succeeded
            completedRun.finishedAt = Date()
            completedRun.billedUSD = Decimal(0.0015)
            completedRun.outputsMeta = .object([
                "image_count": .number(1),
                "processing_time": .number(2.5)
            ])
            
            persistence.updateRun(completedRun)
            loadDemoData()
        }
        
        loadDemoData()
    }
    
    private func createSampleArtifact() {
        // Create a sample image artifact
        let artifact = Artifact(
            kind: "image",
            mimeType: "image/png",
            storage: "local",
            uri: "file:///tmp/demo_image_\(Date().timeIntervalSince1970).png",
            contentHash: "demo_hash_\(Int.random(in: 1000...9999))",
            sizePx: CGSize(width: 512, height: 512)
        )
        
        persistence.storeArtifact(artifact)
        loadDemoData()
    }
    
    private func clearAll() {
        // Clear demo data (in a real app, you'd want more selective clearing)
        demoRuns.removeAll()
        demoArtifacts.removeAll()
    }
    
    private func loadDemoData() {
        demoRuns = persistence.getRecentRuns(limit: 10)
        demoArtifacts = Array(persistence.artifacts.values).sorted { $0.createdAt > $1.createdAt }.prefix(10).map { $0 }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct RunRowView: View {
    let run: Run
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: run.status.iconName)
                .foregroundColor(colorForStatus(run.status))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(run.model.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Started: \(run.startedAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(run.status.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(colorForStatus(run.status))
                
                if run.duration != nil {
                    Text(run.durationDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Running...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func colorForStatus(_ status: RunStatus) -> Color {
        switch status {
        case .queued: return .orange
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
}

struct ArtifactDemoRowView: View {
    let artifact: Artifact
    
    var body: some View {
        HStack(spacing: 12) {
            // Artifact type indicator
            Image(systemName: artifact.iconName)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(artifact.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(artifact.mimeType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(artifact.kind.capitalized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                
                if artifact.isImage {
                    Text(artifact.sizeDisplay)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Created: \(artifact.createdAt, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct RunModelsDemo_Previews: PreviewProvider {
    static var previews: some View {
        RunModelsDemo()
    }
}
