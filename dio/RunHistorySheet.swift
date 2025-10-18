import SwiftUI

// MARK: - Run History Sheet

struct RunHistorySheet: View {
    let node: Node
    @SwiftUI.Binding var isPresented: Bool
    
    @StateObject private var persistence = RunPersistence.shared
    @State private var runs: [Run] = []
    @State private var selectedRun: Run?
    @State private var showArtifactDetail = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {                
                if runs.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "clock")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Runs Yet")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("This node hasn't been executed yet. Run the graph to see execution history here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Runs list
                    List(runs, id: \.id) { run in
                        RunHistoryRowView(
                            run: run,
                            onTap: { selectedRun = run }
                        )
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Run History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadRuns()
        }
        .sheet(isPresented: $showArtifactDetail) {
            if let run = selectedRun {
                RunDetailSheet(run: run, isPresented: $showArtifactDetail)
            }
        }
        .onChange(of: selectedRun) { oldValue, newValue in
            if newValue != nil {
                showArtifactDetail = true
            }
        }
    }
    
    private func loadRuns() {
        runs = persistence.getRunsForNode(node.id)
    }
}

// MARK: - Run History Row View

struct RunHistoryRowView: View {
    let run: Run
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Image(systemName: run.status.iconName)
                    .font(.title2)
                    .foregroundColor(statusColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(run.model.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(run.status.displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(statusColor)
                    }
                    
                    HStack {
                        Text("Started: \(run.startedAt, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if let duration = run.duration {
                            Text(durationDisplay(duration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let cost = run.billedUSD {
                        HStack {
                            Text("Cost: \(costDisplay(cost))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                    }
                    
                    if let errorMessage = run.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    
                    // Quick preview of input parameters
                    if let prompt = extractPromptFromInputParams(run.inputParams) {
                        Text("Prompt: \(prompt)")
                            .font(.caption)
                            .foregroundColor(.blue)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var statusColor: Color {
        switch run.status {
        case .queued: return .orange
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
    
    private func durationDisplay(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    private func costDisplay(_ cost: Decimal) -> String {
        return String(format: "$%.4f", cost as NSDecimalNumber)
    }
    
    private func extractPromptFromInputParams(_ inputParams: JSONValue) -> String? {
        // Extract prompt from input parameters for quick preview
        if case .object(let dict) = inputParams,
           case .string(let prompt) = dict["prompt"] {
            return prompt
        }
        return nil
    }
}

// MARK: - Run Detail Sheet

struct RunDetailSheet: View {
    let run: Run
    @SwiftUI.Binding var isPresented: Bool
    
    @StateObject private var persistence = RunPersistence.shared
    @State private var artifacts: [Artifact] = []
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Run info
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Run Details")
                            .font(.headline)
                        
                        InfoRow(label: "Status", value: run.status.displayName, valueColor: statusColor)
                        InfoRow(label: "Model", value: run.model.displayName)
                        InfoRow(label: "Started", value: run.startedAt.formatted())
                        
                        if let finishedAt = run.finishedAt {
                            InfoRow(label: "Finished", value: finishedAt.formatted())
                        }
                        
                        if let duration = run.duration {
                            InfoRow(label: "Duration", value: durationDisplay(duration))
                        }
                        
                        if let cost = run.billedUSD {
                            InfoRow(label: "Cost", value: costDisplay(cost))
                        }
                        
                        if let errorCode = run.errorCode {
                            InfoRow(label: "Error Code", value: errorCode, valueColor: .red)
                        }
                        
                        if let errorMessage = run.errorMessage {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Error Message")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Artifacts
                    if !artifacts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Output Artifacts")
                                .font(.headline)
                            
                            ForEach(artifacts, id: \.id) { artifact in
                                ArtifactRowView(artifact: artifact)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Input Parameters
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Input Parameters")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resolved Args (after bindings):")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text(run.inputParams.displayString)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resolved Inputs (from upstream ports):")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text(run.resolvedInputs.displayString)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Node Args Snapshot (original):")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            Text(run.nodeArgsSnapshot.displayString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Output metadata
                    if let outputsMeta = run.outputsMeta {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Output Metadata")
                                .font(.headline)
                            
                            Text(outputsMeta.displayString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }

                    // Vendor Meta (includes adapter logs)
                    if let meta = run.adapterDebug {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Adapter Logs & Metadata")
                                .font(.headline)

                            // Attempt to extract logs array from vendor meta
                            let logsText: String = {
                                if case .object(let dict) = meta, let logsValue = dict["logs"] {
                                    switch logsValue {
                                    case .array(let arr):
                                        return arr.compactMap { v in
                                            if case .string(let s) = v { return s } else { return nil }
                                        }.joined(separator: "\n")
                                    case .string(let s):
                                        return s
                                    default:
                                        return meta.displayString
                                    }
                                }
                                return meta.displayString
                            }()

                            ScrollView {
                                Text(logsText)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                            }
                            .frame(minHeight: 120)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .navigationTitle("Run Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadArtifacts()
        }
    }
    
    private var statusColor: Color {
        switch run.status {
        case .queued: return .orange
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
    
    private func loadArtifacts() {
        artifacts = persistence.getArtifactsForRun(run.id)
    }
    
    private func durationDisplay(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    private func costDisplay(_ cost: Decimal) -> String {
        return String(format: "$%.4f", cost as NSDecimalNumber)
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String
    let valueColor: Color
    
    init(label: String, value: String, valueColor: Color = .primary) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
        }
    }
}

struct ArtifactRowView: View {
    let artifact: Artifact
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: artifact.iconName)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(artifact.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack {
                    Text(artifact.kind.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if artifact.isImage, let size = artifact.sizePx {
                        Text("\(Int(size.width))×\(Int(size.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if artifact.isVideo, let duration = artifact.durationSec {
                        Text(String(format: "%.1fs", duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}
