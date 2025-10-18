import Foundation
import SwiftUI
import Combine

// MARK: - Execution Engine Demo

struct ExecutionEngineDemo: View {
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var demoGraph: Graph?
    @State private var executionHistory: [GraphExecution] = []
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Execution Engine Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Test the execution engine with sample graphs")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Demo Controls
                VStack(alignment: .leading, spacing: 10) {
                    Text("Demo Controls")
                        .font(.headline)
                    
                    HStack(spacing: 10) {
                        Button("Create Sample Graph") {
                            createSampleGraph()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(executionEngine.isExecuting)
                        
                        Button("Execute Graph") {
                            executeCurrentGraph()
                        }
                        .buttonStyle(.bordered)
                        .disabled(demoGraph == nil || executionEngine.isExecuting)
                        
                        Button("Cancel Execution") {
                            executionEngine.cancelExecution()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                        .disabled(!executionEngine.isExecuting)
                    }
                }
                
                Divider()
                
                // Execution Status
                if executionEngine.isExecuting {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Execution Status")
                            .font(.headline)
                        
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Executing graph...")
                                .font(.subheadline)
                        }
                        
                        if let execution = executionEngine.currentExecution {
                            ExecutionStatusView(execution: execution)
                        }
                        
                        // Active Runs
                        if !executionEngine.activeRuns.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Active Node Executions")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                ForEach(Array(executionEngine.activeRuns.values), id: \.id) { run in
                                    HStack {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundColor(.blue)
                                        Text("Node \(run.nodeID.uuidString.prefix(8))...")
                                            .font(.caption)
                                        Spacer()
                                        Text(run.status.displayName)
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
                
                // Graph Visualization
                if let graph = demoGraph {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current Graph")
                            .font(.headline)
                        
                        GraphVisualizationView(graph: graph)
                            .frame(height: 200)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                
                // Recent Executions
                if !executionHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Execution History")
                            .font(.headline)
                        
                        ForEach(executionHistory.prefix(5), id: \.id) { execution in
                            ExecutionHistoryRowView(execution: execution)
                        }
                    }
                }
                
                // Recent Runs
                let recentRuns = persistence.getRecentRuns(limit: 10)
                if !recentRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Runs")
                            .font(.headline)
                        
                        ForEach(recentRuns.prefix(5), id: \.id) { run in
                            RunRowView(run: run)
                        }
                    }
                }
                
                
                Spacer()
            }
        }
        .padding()
        .onAppear {
            loadExecutionHistory()
            setupExecutionStatusObserver()
        }
    }
    
    // MARK: - Demo Methods
    
    private func createSampleGraph() {
        // Create a simple text -> image workflow
        let textNode = Node.textPrompt(
            frame: CGRect(x: 10, y: 50, width: 100, height: 80),
            text: "A beautiful sunset over mountains"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 120, y: 50, width: 100, height: 80),
            prompt: "",
            size: CGSize(width: 512, height: 512)
        )
        
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        
        // Create bindings using proper port names (like in the working example)
        let textOutputPort = textNode.ports.first { $0.name == "text_output" }!
        
        // Text -> Image Generation
        graph.addBinding(
            sourcePortID: textOutputPort.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        
        
        demoGraph = graph
    }
    
    private func executeCurrentGraph() {
        guard let graph = demoGraph else { return }
        
        Task {
            await executionEngine.execute(graph: graph)
            await MainActor.run {
                loadExecutionHistory()
            }
        }
    }
    
    private func loadExecutionHistory() {
        // In a real implementation, you'd load from persistence
        // For now, we'll just show the current execution if it exists
        if let currentExecution = executionEngine.currentExecution {
            executionHistory = [currentExecution]
        }
    }
    
    
    private func setupExecutionStatusObserver() {
        // Observe changes to the execution engine's current execution
        executionEngine.$currentExecution
            .receive(on: DispatchQueue.main)
            .sink { currentExecution in
                if let currentExecution = currentExecution {
                    self.executionHistory = [currentExecution]
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Views

struct ExecutionStatusView: View {
    let execution: GraphExecution
    
    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Graph Execution")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Started: \(execution.startedAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let duration = execution.duration {
                    Text("Duration: \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(execution.status.rawValue.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(statusColor)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var statusIcon: String {
        switch execution.status {
        case .running: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .canceled: return "stop.circle.fill"
        }
    }
    
    private var statusColor: Color {
        switch execution.status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
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
}

struct GraphVisualizationView: View {
    let graph: Graph
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Draw nodes
                ForEach(Array(graph.nodes.values), id: \.id) { node in
                    NodeVisualizationView(node: node)
                        .position(
                            x: node.frame.midX,
                            y: node.frame.midY
                        )
                }
                
                // Draw edges
                ForEach(Array(graph.edges.values), id: \.id) { edge in
                    EdgeVisualizationView(edge: edge, nodes: graph.nodes)
                }
            }
        }
    }
}

struct NodeVisualizationView: View {
    let node: Node
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: node.kind.iconName)
                .font(.title2)
            Text(node.kind.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(width: 100, height: 60)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 2)
    }
}

struct EdgeVisualizationView: View {
    let edge: Edge
    let nodes: [UUID: Node]
    
    var body: some View {
        Path { path in
            guard let sourceNode = nodes[edge.source.nodeID.raw],
                  let targetNode = nodes[edge.target.nodeID.raw] else { return }
            
            let startPoint = CGPoint(x: sourceNode.frame.maxX, y: sourceNode.frame.midY)
            let endPoint = CGPoint(x: targetNode.frame.minX, y: targetNode.frame.midY)
            
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        .stroke(Color.blue, lineWidth: 2)
    }
}

struct ExecutionHistoryRowView: View {
    let execution: GraphExecution
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Graph \(execution.graphID.uuidString.prefix(8))...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("\(execution.startedAt, style: .date) at \(execution.startedAt, style: .time)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(execution.status.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                    
                    if let duration = execution.duration {
                        Text(formatDuration(duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            if execution.status == .failed {
                Text(execution.errorMessage ?? "Unknown error")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        switch execution.status {
        case .running: return "play.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .canceled: return "stop.circle"
        }
    }
    
    private var statusColor: Color {
        switch execution.status {
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
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
}

// MARK: - Preview

struct ExecutionEngineDemo_Previews: PreviewProvider {
    static var previews: some View {
        ExecutionEngineDemo()
    }
}
