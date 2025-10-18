import SwiftUI

// MARK: - Image Node Page View

struct ImageNodePageView: View {
    let node: Node
    let connectedBindingsCount: Int
    let onClose: () -> Void
    let onUpdateNode: ((Node) -> Void)?
    let onDelete: (() -> Void)?
    
    @State private var isConfirmingDelete: Bool = false
    @StateObject private var persistence = RunPersistence.shared
    @State private var runs: [Run] = []
    @State private var showRunHistory = false
    @State private var generatedImages: [Artifact] = []
    
    init(node: Node, connectedBindingsCount: Int, onClose: @escaping () -> Void, onUpdateNode: ((Node) -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.node = node
        self.connectedBindingsCount = connectedBindingsCount
        self.onClose = onClose
        self.onUpdateNode = onUpdateNode
        self.onDelete = onDelete
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.kind.displayName)
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text("Image Generation Node")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Close button
                            Button(action: onClose) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Node metadata
                        HStack(spacing: 16) {
                            Label("\(node.ports.count) Ports", systemImage: "cable.connector")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Label("\(connectedBindingsCount) Connections", systemImage: "link")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let width = node.getArg("/size/width", as: Double.self),
                               let height = node.getArg("/size/height", as: Double.self) {
                                Label("\(Int(width))×\(Int(height))", systemImage: "rectangle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Prompt Section
                    if let prompt = node.getArg("/prompt", as: String.self), !prompt.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Prompt")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(prompt)
                                .font(.body)
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Generated Images Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Generated Images")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            if !runs.isEmpty {
                                Button("View History") {
                                    showRunHistory = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                        }
                        
                        if !generatedImages.isEmpty {
                            LazyVGrid(columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ], spacing: 12) {
                                ForEach(generatedImages, id: \.id) { artifact in
                                    FullPageGeneratedImageView(artifact: artifact)
                                }
                            }
                        } else {
                            // Empty state
                            VStack(spacing: 16) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 64))
                                    .foregroundColor(.secondary)
                                
                                VStack(spacing: 8) {
                                    Text("No generated images yet")
                                        .font(.title3)
                                        .fontWeight(.medium)
                                    
                                    Text("Run this node to generate images")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 48)
                            .background(Color(.systemGray6))
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Run History Preview
                    if !runs.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Recent Runs")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                                
                                Button("View All") {
                                    showRunHistory = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            
                            // Show up to 5 most recent runs
                            ForEach(Array(runs.prefix(5)), id: \.id) { run in
                                FullPageRunHistoryRow(run: run)
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Action Buttons
                    VStack(spacing: 12) {
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
                                        .font(.system(size: 16))
                                    Text(isConfirmingDelete ? "Confirm Remove?" : "Remove Node")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(isConfirmingDelete ? Color.red : Color(.systemGray5))
                                .foregroundColor(isConfirmingDelete ? .white : .primary)
                                .cornerRadius(12)
                            }
                        }
                        
                        Button(action: onClose) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16))
                                Text("Done")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .foregroundColor(.white)
                            .background(.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadRuns()
            loadGeneratedImages()
        }
        .onChange(of: runs) { oldValue, newValue in
            loadGeneratedImages()
        }
        .sheet(isPresented: $showRunHistory) {
            RunHistorySheet(node: node, isPresented: $showRunHistory)
        }
    }
    
    private func loadRuns() {
        runs = persistence.getRunsForNode(node.id)
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

// MARK: - Full Page Generated Image View

struct FullPageGeneratedImageView: View {
    let artifact: Artifact
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .aspectRatio(1, contentMode: .fit)
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else if loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundColor(.orange)
                        Text("Failed to load")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipped()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(.secondary)
                }
            }
            .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 4) {
                if let sizePx = artifact.sizePx {
                    Text("\(Int(sizePx.width))×\(Int(sizePx.height))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
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

// MARK: - Full Page Run History Row

struct FullPageRunHistoryRow: View {
    let run: Run
    
    var body: some View {
        HStack(spacing: 16) {
            // Status indicator
            Image(systemName: run.status.iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(statusColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.model.displayName)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(run.status.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                }
                
                HStack {
                    Text("Started: \(run.startedAt, style: .time)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if run.duration != nil {
                        Text(run.durationDisplay)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let cost = run.billedUSD {
                    HStack {
                        Text("Cost: \(costDisplay(cost))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
    
    return ImageNodePageView(
        node: sampleNode,
        connectedBindingsCount: 1,
        onClose: {},
        onUpdateNode: nil,
        onDelete: {}
    )
}
