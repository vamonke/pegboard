import SwiftUI

// MARK: - Node Bottom Sheet

struct NodeBottomSheet: View {
    let node: Node
    let connectedBindingsCount: Int
    let onClose: () -> Void
    let onUpdateNode: ((Node) -> Void)?
    let onDelete: (() -> Void)?
    
    @State private var tempNode: Node
    @State private var isConfirmingDelete: Bool = false
    @StateObject private var persistence = RunPersistence.shared
    @State private var runs: [Run] = []
    @State private var showRunHistory = false
    
    init(node: Node, connectedBindingsCount: Int, onClose: @escaping () -> Void, onUpdateNode: ((Node) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.node = node
        self.connectedBindingsCount = connectedBindingsCount
        self.onClose = onClose
        self.onUpdateNode = onUpdateNode
        self.onDelete = onDelete
        self._tempNode = State(initialValue: node)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(node.kind.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    
                    // Show save/cancel buttons for text prompt nodes with changes
                    if node.kind == .textPrompt {
                        Button(action: {
                            onUpdateNode?(tempNode)
                            onClose()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                    }
                }
                
                // Content based on node type
                Group {
                    switch node.kind {
                    case .textPrompt:
                        TextPromptBottomSheetView(node: $tempNode)
                    case .imageGeneration:
                        ImageGenerationBottomSheetView(node: node, runs: runs)
                    default:
                        // Default placeholder content for other node types
                        VStack(alignment: .leading, spacing: 12) {                   
                            // Show some basic node information
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Node ID: \(node.id.uuidString)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                
                                Text("Ports: \(node.ports.count)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                
                                Text("Connected Bindings: \(connectedBindingsCount)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                
                // Run History Section
                if !runs.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Runs")
                                .font(.headline)
                            
                            Spacer()
                            
                            Button("View All") {
                                showRunHistory = true
                            }
                            .font(.caption)
                            .foregroundColor(.blue) 
                        }
                        
                        // Show up to 3 most recent runs
                        ForEach(Array(runs.prefix(3)), id: \.id) { run in
                            RunHistoryPreviewRow(run: run)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                if let onDelete = onDelete {
                    Button(role: isConfirmingDelete ? .destructive : nil) {
                        if isConfirmingDelete {
                            onDelete()
                            onClose()
                        } else {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isConfirmingDelete = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isConfirmingDelete ? "trash.fill" : "trash")
                                .font(.system(size: 14))
                            Text(isConfirmingDelete ? "Confirm Remove?" : "Remove")
                        }
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                    }
                }
                
                Button(action: {
                    onUpdateNode?(tempNode)
                    onClose()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14))
                        Text("Done")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(.white)
                    .background(.blue)
                    .cornerRadius(10)
                }
                
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            loadRuns()
        }
        .sheet(isPresented: $showRunHistory) {
            RunHistorySheet(node: node, isPresented: $showRunHistory)
        }
    }
    
    private func loadRuns() {
        runs = persistence.getRunsForNode(node.id)
    }
}

// MARK: - Text Prompt Bottom Sheet View

struct TextPromptBottomSheetView: View {
    @SwiftUI.Binding var node: Node
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {            
            let text = node.getArg("/text", as: String.self) ?? ""
            ZStack(alignment: .topLeading) {
                TextEditor(text: SwiftUI.Binding(
                    get: { text },
                    set: { newValue in
                        node.setArg("/text", value: newValue)
                    }
                ))
                .frame(minHeight: 120)
                .background(Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .focused($isTextFieldFocused)
                .onAppear {
                    // Focus the text editor when the view appears
                    DispatchQueue.main.asyncAfter(deadline: .now()) {
                        isTextFieldFocused = true
                    }
                }
                if text.isEmpty {
                    Text("Your prompt goes here...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            
            // Show some basic node information
            VStack(alignment: .leading, spacing: 8) {
                Text("Node ID: \(node.id.uuidString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Text("Ports: \(node.ports.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Image Generation Bottom Sheet View

struct ImageGenerationBottomSheetView: View {
    let node: Node
    let runs: [Run]
    @StateObject private var persistence = RunPersistence.shared
    @State private var generatedImages: [Artifact] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Show prompt if available
            if let prompt = node.getArg("/prompt", as: String.self), !prompt.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    Text(prompt)
                        .font(.body)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }
            
            // Show generated images
            if !generatedImages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Generated Images")
                        .font(.headline)
                        .fontWeight(.medium)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        ForEach(generatedImages, id: \.id) { artifact in
                            GeneratedImageView(artifact: artifact)
                        }
                    }
                }
            } else {
                // Show placeholder when no images
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No generated images yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Run this node to generate images")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Show some basic node information
            VStack(alignment: .leading, spacing: 8) {
                Text("Node ID: \(node.id.uuidString)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                Text("Ports: \(node.ports.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                
                let width = node.getArg("/size/width", as: Double.self)
                let height = node.getArg("/size/height", as: Double.self)
                if let w = width, let h = height {
                    Text("Size: \(Int(w))×\(Int(h))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            loadGeneratedImages()
        }
        .onChange(of: runs) { oldValue, newValue in
            loadGeneratedImages()
        }
    }
    
    private func loadGeneratedImages() {
        // Get all successful runs for this node
        let successfulRuns = runs.filter { $0.status == .succeeded }
        
        var images: [Artifact] = []
        
        for run in successfulRuns {
            // Get primary artifact for each successful run
            if let primaryArtifact = persistence.getPrimaryArtifactForRun(run.id),
               primaryArtifact.isImage {
                images.append(primaryArtifact)
            }
        }
        
        // Sort by creation date (newest first)
        generatedImages = images.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Generated Image View

struct GeneratedImageView: View {
    let artifact: Artifact
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray5))
                    .aspectRatio(1, contentMode: .fit)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if loadError {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundColor(.orange)
                        Text("Failed to load")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                if let sizePx = artifact.sizePx {
                    Text("\(Int(sizePx.width))×\(Int(sizePx.height))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(artifact.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = URL(string: artifact.uri) else {
            loadError = true
            isLoading = false
            return
        }
        
        if artifact.uri.hasPrefix("asset://") {
            // Handle asset URLs
            let assetName = String(artifact.uri.dropFirst(8)) // Remove "asset://" prefix
            if let uiImage = UIImage(named: assetName) {
                image = uiImage
                isLoading = false
            } else {
                loadError = true
                isLoading = false
            }
        } else if artifact.uri.hasPrefix("file://") {
            // Handle file URLs
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async {
                        image = uiImage
                        isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        loadError = true
                        isLoading = false
                    }
                }
            }
        } else {
            // Handle other URL types (could be remote URLs)
            DispatchQueue.global(qos: .userInitiated).async {
                if let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data) {
                    DispatchQueue.main.async {
                        image = uiImage
                        isLoading = false
                    }
                } else {
                    DispatchQueue.main.async {
                        loadError = true
                        isLoading = false
                    }
                }
            }
        }
    }
}

// MARK: - Run History Preview Row

struct RunHistoryPreviewRow: View {
    let run: Run
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: run.status.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(run.model.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
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
                    
                    if run.duration != nil {
                        Text(run.durationDisplay)
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
            }
        }
        .padding(.vertical, 4)
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
    
    private func costDisplay(_ cost: Decimal) -> String {
        return String(format: "$%.4f", cost as NSDecimalNumber)
    }
}

#Preview {
    // Create a sample image generation node for preview
    let sampleNode = Node.imageGeneration(
        frame: CGRect(x: 0, y: 0, width: 240, height: 240),
        prompt: "A beautiful sunset over mountains"
    )
    
    return NodeBottomSheet(
        node: sampleNode,
        connectedBindingsCount: 1,
        onClose: {},
        onUpdateNode: nil,
        onDelete: {}
    )
}
