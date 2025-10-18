import SwiftUI
import AVKit
import AVFoundation
import ImageIO
import Combine

// MARK: - Full Page Output Preview View

struct OutputPreviewView: View {
    let node: Node
    let isPresented: SwiftUI.Binding<Bool>
    
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var currentRunIndex: Int = 0
    @State private var currentImageIndex: Int = 0
    @State private var showRunDetails: Bool = false
    
    init(node: Node, isPresented: SwiftUI.Binding<Bool>) {
        self.node = node
        self.isPresented = isPresented
    }
    
    // Computed properties for run navigation
    private var allRuns: [Run] {
        let runs = persistence.getRunsForNode(node.id)
        return runs
    }
    
    private var successfulRuns: [Run] {
        let successful = allRuns.filter { $0.status == .succeeded }
        return successful
    }
    
    private var currentRun: Run? {
        guard currentRunIndex < successfulRuns.count else { 
            return nil 
        }
        let run = successfulRuns[currentRunIndex]
        return run
    }
    
    private var currentRunOutputs: [Artifact] {
        guard let run = currentRun else { 
            return [] 
        }
        let outputs = persistence.getArtifactsForRun(run.id)
        return outputs
    }
    
    // Fallback to latest run if no successful runs
    private var fallbackRun: Run? {
        let run = executionEngine.getLatestRunForNode(node.id)
        return run
    }
    
    private var fallbackOutputs: [Artifact] {
        let outputs = executionEngine.getLatestOutputsForNode(node.id)
        return outputs
    }
    
    var body: some View {
        ZStack {
            // Black background like iOS Photos
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar with navigation and controls
                VStack(spacing: 12) {
                    // Main top bar
                    HStack {
                        Button(action: {
                            isPresented.wrappedValue = false
                        }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        
                        Spacer()

                        if successfulRuns.count > 1 {
                          Text("\(currentRunIndex + 1) / \(successfulRuns.count)")
                              .font(.subheadline)
                              .fontWeight(.medium)
                              .foregroundColor(.white)
                        }

                        Spacer()
                        
                        // Run details toggle
                        Button(action: {
                            showRunDetails.toggle()
                        }) {
                            Image(systemName: showRunDetails ? "info.circle.fill" : "info.circle")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // Main content area with swipe gestures
                if !currentRunOutputs.isEmpty {
                    GeometryReader { geometry in
                      FullPageOutputContentView(
                          artifact: currentRunOutputs[currentImageIndex],
                          node: node,
                          geometry: geometry
                      )
                    }
                    .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Only handle horizontal swipes if there are multiple successful runs
                            guard successfulRuns.count > 1 else { return }
                            
                            let threshold: CGFloat = 50
                            if value.translation.width > threshold {
                                // Swipe right - go to previous run
                                if currentRunIndex > 0 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentRunIndex -= 1
                                        currentImageIndex = 0
                                    }
                                }
                            } else if value.translation.width < -threshold {
                                // Swipe left - go to next run
                                if currentRunIndex < successfulRuns.count - 1 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentRunIndex += 1
                                        currentImageIndex = 0
                                    }
                                }
                            }
                        }
                )
                } else {
                    EmptyView()
                }
                
                
                // Bottom section with run details or page indicators
                VStack(spacing: 0) {
                    if showRunDetails {
                        RunDetailsView(node: node, currentRun: currentRun)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Page indicators for multiple outputs within current run
                    if currentRunOutputs.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<currentRunOutputs.count, id: \.self) { index in
                                Circle()
                                    .fill(index == currentImageIndex ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showRunDetails)
    }
}

// MARK: - Full Page Output Content View

struct FullPageOutputContentView: View {
    let artifact: Artifact
    let node: Node
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 0) {
            if artifact.isImage {
                FullPageImageView(artifact: artifact, node: node, geometry: geometry)
            } else if artifact.isVideo {
                FullPageVideoView(artifact: artifact, geometry: geometry)
            } else if artifact.isText {
                FullPageTextView(artifact: artifact, geometry: geometry)
            } else {
                FullPageGenericView(artifact: artifact, geometry: geometry)
            }
        }
    }
}

// MARK: - Full Page Image View

struct FullPageImageView: View {
    let artifact: Artifact
    let node: Node
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if artifact.uri == "asset://image" {
                // Temporary dummy logic: choose cat or dog asset by prompt
                let promptHint = node.getArg("/prompt", as: String.self)
                let isCat = promptHint?.lowercased().contains("cat") == true
                Image(isCat ? "cat" : "dog")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                    .clipped()
            } else {
                // Display actual saved image artifact if we have a local file URL
                if let url = ArtifactManager.shared.getArtifactURL(artifact) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                                .clipped()
                        case .failure(_):
                            VStack(spacing: 16) {
                                Image(systemName: "photo")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white.opacity(0.6))
                                
                                Text("Failed to load image")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Text(artifact.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .empty:
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Fallback if we cannot resolve a URL
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(artifact.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Full Page Video View

struct FullPageVideoView: View {
    let artifact: Artifact
    let geometry: GeometryProxy
    
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let url = ArtifactManager.shared.getArtifactURL(artifact) {
                VideoPlayer(player: player)
                    .onAppear {
                        // Initialize and start playback when the view appears
                        let avPlayer = AVPlayer(url: url)
                        player = avPlayer
                        avPlayer.play()
                    }
                    .onDisappear {
                        // Stop playback and release player when leaving
                        player?.pause()
                        player = nil
                    }
                    .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
            } else {
                // Fallback if we cannot resolve a URL
                VStack(spacing: 16) {
                    Image(systemName: "video")
                        .font(.system(size: 48))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Unable to load video")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(artifact.displayName)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Full Page Text View

struct FullPageTextView: View {
    let artifact: Artifact
    let geometry: GeometryProxy
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if artifact.uri.hasPrefix("data:text/plain;base64,") {
                    // Extract and display the actual text content
                    let base64String = String(artifact.uri.dropFirst("data:text/plain;base64,".count))
                    if let data = Data(base64Encoded: base64String),
                       let textContent = String(data: data, encoding: .utf8) {
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                
                                Text("Text Output")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Spacer()
                            }
                            
                            Text(textContent)
                                .font(.body)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                        }
                        .padding(24)
                    } else {
                        // Fallback if base64 decoding fails
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text("Failed to decode text")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    // Fallback for other text artifacts
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(artifact.displayName)
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Full Page Generic View

struct FullPageGenericView: View {
    let artifact: Artifact
    let geometry: GeometryProxy
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: artifact.iconName)
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))
            
            Text(artifact.displayName)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Text("Generic output type")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Run Details View

struct RunDetailsView: View {
    let node: Node
    let currentRun: Run?
    
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var computedResolution: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Run Details")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Run information
            if let run = currentRun {
                VStack(alignment: .leading, spacing: 12) {
                    // Status
                    HStack {
                        Text("Status:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Image(systemName: run.status.iconName)
                                .font(.caption)
                                .foregroundColor(statusColor)
                            
                            Text(run.status.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor)
                        }
                    }
                    
                    // Timestamp
                    HStack {
                        Text("Created:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text(run.startedAt, style: .time)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    
                    // Duration (if completed)
                    if run.status == .succeeded || run.status == .failed {
                        HStack {
                            Text("Duration:")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                            
                            if let completedAt = run.finishedAt {
                                let duration = completedAt.timeIntervalSince(run.startedAt)
                                Text(formatDuration(duration))
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    // Node type
                    HStack {
                        Text("Node Type:")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        
                        Spacer()
                        
                        Text(node.kind.displayName)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }

                    // Resolution (from primary artifact)
                    if let artifact = persistence.getPrimaryArtifactForRun(run.id) {
                        HStack {
                            Text("Resolution:")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            
                            Spacer()
                            
                            Text(computedResolution ?? artifact.sizeDisplay)
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                    }
                }
            } else {
                Text("No run information available")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(20)
        .background(Color.black.opacity(0.8))
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .onAppear {
            if let run = currentRun {
                computeResolution(for: run)
            }
        }
        .onChange(of: currentRun?.id) {
            if let run = currentRun {
                computeResolution(for: run)
            } else {
                computedResolution = nil
            }
        }
        .onReceive(persistence.$runArtifacts) { _ in
            if let run = currentRun { computeResolution(for: run) }
        }
        .onReceive(persistence.$runs) { _ in
            if let run = currentRun { computeResolution(for: run) }
        }
    }
    
    private var statusColor: Color {
        guard let run = currentRun else {
            return .white.opacity(0.7)
        }
        
        switch run.status {
        case .queued: return .orange
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .canceled: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else if duration < 3600 {
            return String(format: "%.1fm", duration / 60)
        } else {
            return String(format: "%.1fh", duration / 3600)
        }
    }

    private func computeResolution(for run: Run) {
        computedResolution = nil
        guard let artifact = persistence.getPrimaryArtifactForRun(run.id) else { return }
        if let size = artifact.sizePx {
            computedResolution = "\(Int(size.width))×\(Int(size.height))"
            return
        }
        if let meta = run.outputsMeta {
            let wPtr = JSONPointer("/size/width")
            let hPtr = JSONPointer("/size/height")
            let w = jsonDouble(wPtr.get(from: meta))
            let h = jsonDouble(hPtr.get(from: meta))
            if let w = w, let h = h {
                computedResolution = "\(Int(w))×\(Int(h))"
                return
            }
            // Fallback for adapters that place dimensions under images[0]
            let wPtrImg = JSONPointer("/images/0/width")
            let hPtrImg = JSONPointer("/images/0/height")
            let wImg = jsonDouble(wPtrImg.get(from: meta))
            let hImg = jsonDouble(hPtrImg.get(from: meta))
            if let w = wImg, let h = hImg {
                computedResolution = "\(Int(w))×\(Int(h))"
                return
            }
        }
        guard let url = URL(string: artifact.uri) else { return }
        if artifact.isImage {
            if let size = getLocalImageSize(url: url) {
                computedResolution = "\(Int(size.width))×\(Int(size.height))"
            }
        } else if artifact.isVideo {
            if let size = getLocalVideoSize(url: url) {
                computedResolution = "\(Int(size.width))×\(Int(size.height))"
            }
        }
    }

    private func getLocalImageSize(url: URL) -> CGSize? {
        guard url.isFileURL else { return nil }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return CGSize(width: w, height: h)
    }

    private func getLocalVideoSize(url: URL) -> CGSize? {
        guard url.isFileURL else { return nil }
        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            return track.naturalSize
        }
        return nil
    }

    private func jsonDouble(_ value: JSONValue?) -> Double? {
        guard let value = value else { return nil }
        switch value {
        case .number(let n):
            return n
        case .string(let s):
            return Double(s)
        case .bool(let b):
            return b ? 1 : 0
        default:
            return nil
        }
    }
}

// MARK: - Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
