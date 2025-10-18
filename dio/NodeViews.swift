import SwiftUI
import AVFoundation
import AVKit
import ImageIO
import PhotosUI
import Combine

// MARK: - Node View Components

// Generic node card that can display different node types
struct NodeCard: View {
    let node: Node
    let connectedBindings: [Binding]
    let isSelected: Bool
    let onDelete: () -> Void
    let onPortTap: (UUID) -> Void
    let onShowRunHistory: (() -> Void)?
    let onExecuteNode: (() -> Void)?
    let onShowOutputPreview: (() -> Void)?
    let onCardTap: (() -> Void)?
    let onEdit: (() -> Void)?
    let selectedPort: PortDef?
    
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var measuredSize: CGSize = .zero

    init(
        node: Node,
        connectedBindings: [Binding],
        isSelected: Bool,
        onDelete: @escaping () -> Void,
        onPortTap: @escaping (UUID) -> Void,
        onShowRunHistory: (() -> Void)? = nil,
        onExecuteNode: (() -> Void)? = nil,
        onShowOutputPreview: (() -> Void)? = nil,
        onCardTap: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        selectedPort: PortDef? = nil
    ) {
        self.node = node
        self.connectedBindings = connectedBindings
        self.isSelected = isSelected
        self.onDelete = onDelete
        self.onPortTap = onPortTap
        self.onShowRunHistory = onShowRunHistory
        self.onExecuteNode = onExecuteNode
        self.onShowOutputPreview = onShowOutputPreview
        self.onCardTap = onCardTap
        self.onEdit = onEdit
        self.selectedPort = selectedPort
    }
    
    var body: some View {
        ZStack {
            // Main card content (clipped)
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 8) {
                        Text(node.kind.displayName)
                            .font(.subheadline)
                    }
                    Spacer()
                    if let onEdit = onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "ellipsis")
                                .font(.body)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(Color(.systemGray5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit node")
                    }
                }

                if node.kind == .textPrompt {
                    TextPromptNodeView(node: node)
                } else if node.kind == .imageUpload {
                    ImageUploadNodeView(node: node)
                } else if node.kind == .videoUpload {
                    VideoUploadNodeView(node: node)
                }

                // // Display content based on node type
                // Group {
                //     switch node.kind {
                //     case .textPrompt:
                //         TextPromptNodeView(node: node)
                //     case .imageGeneration:
                //         ImageGenerationNodeView(node: node)
                //     case .imageEdit:
                //         ImageEditNodeView(node: node)
                    
                //     default:
                //         Text("Unknown node type")
                //             .foregroundStyle(.secondary)
                //     }
                // }
                
                // Latest outputs display / progress
                LatestOutputsView(nodeID: node.id, node: node, onTap: onShowOutputPreview)
                
                // Node execution button
                if node.kind.isExecutable, let onExecuteNode = onExecuteNode {
                    Button(action: onExecuteNode) {
                        HStack {
                            if executionEngine.activeRuns[node.id] != nil {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "arrow.right")
                                .font(.callout)
                                .foregroundStyle(.white)
                            }
                            Text(executionEngine.activeRuns[node.id] != nil ? "Running" : "Run Model")
                                .font(.callout)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(executionEngine.activeRuns[node.id] != nil ? .secondary : .primary)
                        .cornerRadius(10)
                    }
                    .disabled(executionEngine.isExecuting)
                }
            }
            .padding(12)
            .frame(width: 240, alignment: .topLeading)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { measuredSize = proxy.size }
                        .onChange(of: proxy.size) { oldValue, newValue in
                            measuredSize = newValue
                        }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selectionBorderColor, lineWidth: isSelected ? 3 : 2)
            )
            .preference(key: NodeSizePreferenceKey.self, value: [node.id: measuredSize])
            .contentShape(Rectangle())
            .onTapGesture {
                onCardTap?()
            }
            
            // Input ports (positioned outside clipping at the top of the card)
            if !visibleInputPorts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(visibleInputPorts, id: \.id) { port in
                        let isConnected = connectedBindings.contains { binding in
                            binding.argPath == node.argPath(for: port)
                        }
                        ConnectionPort(
                            port: port,
                            isConnected: isConnected,
                            isSelected: (selectedPort?.id == port.id),
                            onTap: {
                                onPortTap(port.id)
                            },
                            isSelectionActive: isSelectionActive
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .offset(y: -(measuredSize.height / 2) - 28)
            }
            
            // Output ports (positioned outside clipping at the bottom of the card)
            HStack {
                ForEach(visibleOutputPorts, id: \.id) { port in
                    let isConnected = connectedBindings.contains { binding in
                        binding.sourcePortID == port.id
                    }
                    
                    ConnectionPort(
                        port: port,
                        isConnected: isConnected,
                        isSelected: (selectedPort?.id == port.id),
                        onTap: {
                            onPortTap(port.id)
                        },
                        isSelectionActive: isSelectionActive
                    )
                }
            }
            .offset(y: (measuredSize.height / 2) + 28)
        }
    }
    
    private var selectionBorderColor: Color {
        if isSelected {
            return .blue
        } else {
            return executionStatusColor
        }
    }
    
    private var executionStatusColor: Color {
        // Input nodes don't have execution status
        if node.kind.isInputNode {
            return .clear
        }
        
        if let activeRun = executionEngine.activeRuns[node.id] {
            switch activeRun.status {
            case .running: return .blue
            case .queued: return .orange
            default: return .clear
            }
        } else {
            let latestRun = persistence.getRunsForNode(node.id).first
            switch latestRun?.status {
            case .failed: return .red
            case .canceled: return .gray
            default: return .clear
            }
        }
    }

    private var isSelectionActive: Bool {
        selectedPort != nil
    }

    private var visibleOutputPorts: [PortDef] {
        let outPorts = node.ports.filter { $0.direction == "out" }
        guard isSelectionActive, let selected = selectedPort else { return outPorts }
        
        if selected.direction == "in" {
            // Input port selected: show output ports matching its data type
            return outPorts.filter { $0.dtype == selected.dtype }
        } else {
            // Output port selected: only show this specific output port on its node
            return outPorts.filter { $0.id == selected.id }
        }
    }
    
    private var visibleInputPorts: [PortDef] {
        let inputPorts = node.ports.filter { $0.direction == "in" }
        guard !inputPorts.isEmpty else { return [] }
        
        // Filter out input ports that are already connected
        let unconnectedInputPorts = inputPorts.filter { port in
            let expectedArgPath = node.argPath(for: port)
            return !connectedBindings.contains { binding in
                binding.argPath == expectedArgPath
            }
        }
        
        // If no selection is active, show all unconnected input ports
        guard isSelectionActive, let selected = selectedPort else { return unconnectedInputPorts }
        
        // If this node contains the selected port, hide all its input ports except the selected one
        if selected.direction == "in" {
            let hasSelectedPort = node.ports.contains { $0.id == selected.id }
            if hasSelectedPort {
                return unconnectedInputPorts.filter { $0.id == selected.id }
            }
        } else {
            // If this node contains the selected output port, hide all its input ports
            let hasSelectedPort = node.ports.contains { $0.id == selected.id }
            if hasSelectedPort {
                return []
            }
        }
        
        // Filter input ports to only show those matching the selected port's data type
        return unconnectedInputPorts.filter { $0.dtype == selected.dtype }
    }
}

// MARK: - Node Size Preference

struct NodeSizePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGSize] = [:]
    static func reduce(value: inout [UUID: CGSize], nextValue: () -> [UUID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Node View Components

// Text Prompt Node View
struct TextPromptNodeView: View {
    let node: Node
    
    var body: some View {
        let text = node.getArg("/text", as: String.self) ?? ""
        let displayText = text.isEmpty ? "Your prompt goes here..." : text
        
        Text(displayText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(text.isEmpty ? .secondary : .primary)
            .padding(12)
            .background(Material.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture {
                // Post notification to trigger text prompt editing
                NotificationCenter.default.post(
                    name: NSNotification.Name("EditTextPrompt"),
                    object: nil,
                    userInfo: ["nodeID": node.id]
                )
            }
    }
}

// Image Generation Node View
struct ImageGenerationNodeView: View {
    let node: Node
    
    var body: some View {
        EmptyView()
    }
}

// Image Edit Node View
struct ImageEditNodeView: View {
    let node: Node
    var body: some View {
        EmptyView()
    }
}

// Connection Port View
struct ConnectionPort: View {
    let port: PortDef
    let isConnected: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let isSelectionActive: Bool
    
    init(
        port: PortDef,
        isConnected: Bool,
        isSelected: Bool = false,
        onTap: @escaping () -> Void,
        isSelectionActive: Bool
    ) {
        self.port = port
        self.isConnected = isConnected
        self.isSelected = isSelected
        self.onTap = onTap
        self.isSelectionActive = isSelectionActive
    }
    
    var body: some View {
        Circle()
            .fill(isSelected ? Color.blue : Color(.systemGroupedBackground))
            .frame(width: 40, height: 40)
            .overlay(
                Circle()
                    .stroke(isSelectionActive ? Color.blue : Color.primary.opacity(0.2), lineWidth: 1)
            )
            .overlay(
                Image(systemName: overlayIconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
            )
            .onTapGesture {
                onTap()
            }
    }

    private var overlayIconName: String {
        if isSelected {
            return port.dtype.iconName
        }
        if isSelectionActive {
            return "arrow.down"
        }
        if port.direction == "in" {
            return port.dtype.iconName
        }
        if isConnected {
            return "arrow.down"
        }
        return "plus"
    }
}

// MARK: - Upload Node Views

struct ImageUploadNodeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving: Bool = false
    @State private var isPickerPresented: Bool = false
    @State private var imageURL: URL?
    @State private var imageResolutionText: String?
    @State private var imageFileSizeText: String?
    @State private var isImagePreviewPresented: Bool = false
    let node: Node
    
    var body: some View {
        VStack(spacing: 0) {
            if let image = pickedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isImagePreviewPresented = true
                    }
			} else {
				let savedURLString = node.getArg("/image_url", as: String.self) ?? ""
				if let url = URL(string: savedURLString), !savedURLString.isEmpty {
					AsyncImage(url: url) { phase in
						switch phase {
						case .empty:
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(Color(.systemGray6))
								.frame(height: 120)
								.overlay(ProgressView())
						case .success(let image):
							image
								.resizable()
								.scaledToFit()
								.frame(maxWidth: .infinity)
								.clipShape(RoundedRectangle(cornerRadius: 10))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    isImagePreviewPresented = true
                                }
						case .failure:
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(Color(.systemGray6))
								.frame(height: 120)
								.overlay(
									VStack(spacing: 8) {
										Image(systemName: "exclamationmark.triangle")
											.font(.title2)
											.foregroundStyle(.secondary)
										Text("Failed to load image")
											.font(.caption)
											.foregroundStyle(.secondary)
									}
								)
						@unknown default:
							RoundedRectangle(cornerRadius: 10, style: .continuous)
								.fill(Color(.systemGray6))
								.frame(height: 120)
						}
					}
                    .task(id: savedURLString) {
                        guard !savedURLString.isEmpty, let u = URL(string: savedURLString) else { return }
                        imageURL = u
                        await computeImageInfo(from: u)
                    }
				} else {
                    PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().scaleEffect(0.8) }
                            Image(systemName: "photo.on.rectangle")
                            Text(isSaving ? "Saving..." : (pickedImage == nil ? "Choose Image" : "Choose Another Image"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(10)
                    }
                    .onChange(of: pickerItem) { _, newItem in
                        print("🖼️ ImageUploadNodeView: pickerItem changed. hasNewItem=\(newItem != nil)")
                        guard let newItem else {
                            print("🖼️ ImageUploadNodeView: pickerItem nil after change")
                            return
                        }
                        print("🖼️ ImageUploadNodeView: will handleImageSelection")
                        Task { await handleImageSelection(item: newItem) }
                    }
				}
            }
            // if let res = imageResolutionText, let size = imageFileSizeText {
            //     HStack(spacing: 8) {
            //         Text(res)
            //             .font(.caption2)
            //             .foregroundStyle(.secondary)
            //         Text("•")
            //             .font(.caption2)
            //             .foregroundStyle(.tertiary)
            //         Text(size)
            //             .font(.caption2)
            //             .foregroundStyle(.secondary)
            //         Spacer()
            //     }
            //     .padding(.top, 4)
            // }
            
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .images, photoLibrary: .shared())
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoOpenMediaPicker"))) { notification in
            let recvID = notification.userInfo?["nodeID"] as? UUID
            print("📥 ImageUploadNodeView: received AutoOpenMediaPicker for node id=\(recvID?.uuidString ?? "nil") self=\(node.id)")
            if let id = recvID, id == node.id {
                print("📥 ImageUploadNodeView: setting isPickerPresented = true")
                isPickerPresented = true
            }
        }
        .onChange(of: isPickerPresented) { _, newValue in
            print("📥 ImageUploadNodeView: isPickerPresented changed -> \(newValue)")
        }
        .sheet(isPresented: $isImagePreviewPresented) {
            if let image = pickedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            } else if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().ignoresSafeArea()
                    case .failure(_):
                        VStack { Image(systemName: "photo"); Text("Unable to load image") }
                            .padding()
                    case .empty:
                        ProgressView().scaleEffect(1.2)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
    
    private func handleImageSelection(item: PhotosPickerItem) async {
        print("🖼️ handleImageSelection: start")
        isSaving = true
        defer { isSaving = false }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                print("🖼️ handleImageSelection: got Data size bytes=\(data.count)")
                let mimeType = guessImageMimeType(from: data) ?? "image/jpeg"
                if let uiImage = UIImage(data: data) {
                    await MainActor.run { self.pickedImage = uiImage }
                }
                let artifact = try ArtifactManager.shared.storeArtifact(data: data, kind: "image", mimeType: mimeType)
                if let url = URL(string: artifact.uri) {
                    imageURL = url
                    await computeImageInfo(from: url)
                }
                var updated = node
                updated.setArg("/image_url", value: artifact.uri)
                NotificationCenter.default.post(name: NSNotification.Name("UpdateNode"), object: nil, userInfo: ["node": updated])
                print("🖼️ handleImageSelection: stored artifact uri=\(artifact.uri) and posted UpdateNode")
            }
        } catch {
            print("❌ handleImageSelection: error=\(error)")
        }
    }
    
    private func guessImageMimeType(from data: Data) -> String? {
        // PNG signature
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        // JPEG signature
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        // GIF
        if data.starts(with: [0x47, 0x49, 0x46]) { return "image/gif" }
        return nil
    }
}

struct VideoUploadNodeView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var thumbnail: UIImage?
    @State private var isSaving: Bool = false
	@State private var isLoadingSavedThumb: Bool = false
    @State private var isPickerPresented: Bool = false
    @State private var isPlayerPresented: Bool = false
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var videoResolutionText: String?
    @State private var videoFileSizeText: String?
    let node: Node
    
    var body: some View {
        VStack(spacing: 0) {
            if let image = thumbnail {
                ZStack {
					Image(uiImage: image)
						.resizable()
						.scaledToFit()
						.frame(maxWidth: .infinity)
						.clipShape(RoundedRectangle(cornerRadius: 10))
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 40, height: 40)
                        .overlay(Image(systemName: "play.fill").foregroundStyle(.white))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = videoURL ?? resolveVideoURL() {
                        let av = AVPlayer(url: url)
                        player = av
                        isPlayerPresented = true
                        av.play()
                    }
                }
			} else {
				let savedURLString = node.getArg("/video_url", as: String.self) ?? ""
				if let url = URL(string: savedURLString), !savedURLString.isEmpty {
					RoundedRectangle(cornerRadius: 10, style: .continuous)
						.fill(Color(.systemGray6))
                        .frame(maxWidth: .infinity)
						.overlay(
							ZStack {
								VStack(spacing: 8) {
									Image(systemName: "video")
										.font(.title2)
										.foregroundStyle(.secondary)
									Text("Loading preview...")
										.font(.caption)
										.foregroundStyle(.secondary)
								}
								if isLoadingSavedThumb { ProgressView() }
							}
						)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let av = AVPlayer(url: url)
                            player = av
                            isPlayerPresented = true
                            av.play()
                        }
					.task(id: savedURLString) {
						guard thumbnail == nil, !isLoadingSavedThumb else { return }
						isLoadingSavedThumb = true
						print("🎬 SavedThumb .task: start loading thumbnail from saved URL = \(url)")
						let exists = FileManager.default.fileExists(atPath: url.path)
						print("🎬 SavedThumb .task: file exists at path? \(exists)")
						let thumb = await generateThumbnail(from: url)
                            await MainActor.run {
                                self.thumbnail = thumb
                                self.videoURL = url
                            }
						print("🎬 SavedThumb .task: finished, success = \(thumb != nil)")
						isLoadingSavedThumb = false
					}
				} else {
					// RoundedRectangle(cornerRadius: 10, style: .continuous)
					// 	.fill(Color(.systemGray6))
					// 	.frame(height: 120)
					// 	.overlay(
					// 		VStack(spacing: 8) {
					// 			Image(systemName: "video")
					// 				.font(.title2)
					// 				.foregroundStyle(.secondary)
					// 			Text("Pick a video from library")
					// 				.font(.caption)
					// 				.foregroundStyle(.secondary)
					// 		}
					// 	)
                    PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                        HStack(spacing: 8) {
                            if isSaving { ProgressView().scaleEffect(0.8) }
                            Image(systemName: "video")
                            Text(isSaving ? "Uploading..." : (thumbnail == nil ? "Choose Video" : "Choose Video"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12))
                        .cornerRadius(10)
                    }
                    .onChange(of: pickerItem) { _, newItem in
                        print("🎬 VideoUploadNodeView: pickerItem changed. hasNewItem=\(newItem != nil)")
                        guard let newItem else { return }
                        Task { await handleVideoSelection(item: newItem) }
                    }
				}
            }
            // if let res = videoResolutionText, let size = videoFileSizeText {
            //     HStack(spacing: 8) {
            //         Text(res)
            //             .font(.caption2)
            //             .foregroundStyle(.secondary)
            //         Text("•")
            //             .font(.caption2)
            //             .foregroundStyle(.tertiary)
            //         Text(size)
            //             .font(.caption2)
            //             .foregroundStyle(.secondary)
            //         Spacer()
            //     }
            // }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .videos, photoLibrary: .shared())
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AutoOpenMediaPicker"))) { notification in
            let recvID = notification.userInfo?["nodeID"] as? UUID
            print("📥 VideoUploadNodeView: received AutoOpenMediaPicker for node id=\(recvID?.uuidString ?? "nil") self=\(node.id)")
            if let id = recvID, id == node.id {
                print("📥 VideoUploadNodeView: setting isPickerPresented = true")
                isPickerPresented = true
            }
        }
        .onChange(of: isPickerPresented) { _, newValue in
            print("📥 VideoUploadNodeView: isPickerPresented changed -> \(newValue)")
        }
        .onAppear {
            if videoURL == nil, let initial = resolveVideoURL() {
                videoURL = initial
                Task { await computeVideoInfo(from: initial) }
            }
        }
        .sheet(isPresented: $isPlayerPresented, onDismiss: {
            player?.pause()
            player = nil
        }) {
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                VStack {
                    Image(systemName: "video")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Unable to load video")
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
    }
    
	private func handleVideoSelection(item: PhotosPickerItem) async {
		print("🎬 handleVideoSelection: start")
        isSaving = true
        defer { isSaving = false }
        do {
			print("🎬 handleVideoSelection: attempting loadTransferable URL.self")
			if let url = try await item.loadTransferable(type: URL.self) {
				print("🎬 handleVideoSelection: got URL from picker=\(url.absoluteString)")
				let mimeType = guessVideoMimeType(from: url) ?? "video/quicktime"
				print("🎬 handleVideoSelection: inferred mimeType=\(mimeType)")
				var didAccess = false
				if url.startAccessingSecurityScopedResource() {
					didAccess = true
					print("🔐 handleVideoSelection: started security-scoped access")
				}
				defer {
					if didAccess {
						url.stopAccessingSecurityScopedResource()
						print("🔐 handleVideoSelection: stopped security-scoped access")
					}
				}
                let artifact = try ArtifactManager.shared.storeArtifact(from: url, kind: "video", mimeType: mimeType)
				print("🎬 handleVideoSelection: stored artifact uri=\(artifact.uri)")
				if let savedURL = ArtifactManager.shared.getArtifactURL(artifact) {
					print("🎬 handleVideoSelection: resolved savedURL=\(savedURL)")
					let exists = FileManager.default.fileExists(atPath: savedURL.path)
					print("🎬 handleVideoSelection: file exists at savedURL? \(exists)")
					if let thumb = await generateThumbnail(from: savedURL) {
						print("🎬 handleVideoSelection: generated thumbnail successfully")
                        await MainActor.run {
                            self.thumbnail = thumb
                            self.videoURL = savedURL
                        }
					} else {
						print("⚠️ handleVideoSelection: failed to generate thumbnail from savedURL")
					}
                    await computeVideoInfo(from: savedURL)
				} else {
					print("⚠️ handleVideoSelection: could not resolve savedURL from artifact")
				}
				var updated = node
				updated.setArg("/video_url", value: artifact.uri)
				NotificationCenter.default.post(name: NSNotification.Name("UpdateNode"), object: nil, userInfo: ["node": updated])
				print("🎬 handleVideoSelection: posted UpdateNode notification with updated video_url")
			} else {
				print("⚠️ handleVideoSelection: URL.self loadTransferable returned nil. Trying Data.self")
				if let data = try await item.loadTransferable(type: Data.self) {
					print("🎬 handleVideoSelection: got Data from picker, size bytes=\(data.count)")
					let artifact = try ArtifactManager.shared.storeArtifact(data: data, kind: "video", mimeType: "video/quicktime")
					print("🎬 handleVideoSelection: stored artifact from Data, uri=\(artifact.uri)")
                    if let savedURL = ArtifactManager.shared.getArtifactURL(artifact) {
						print("🎬 handleVideoSelection: resolved savedURL=\(savedURL)")
						let exists = FileManager.default.fileExists(atPath: savedURL.path)
						print("🎬 handleVideoSelection: file exists at savedURL? \(exists)")
						if let thumb = await generateThumbnail(from: savedURL) {
							print("🎬 handleVideoSelection: generated thumbnail successfully (Data path)")
                            await MainActor.run {
                                self.thumbnail = thumb
                                self.videoURL = savedURL
                            }
						} else {
							print("⚠️ handleVideoSelection: failed to generate thumbnail from savedURL (Data path)")
						}
                        await computeVideoInfo(from: savedURL)
					}
					var updated = node
					updated.setArg("/video_url", value: artifact.uri)
					NotificationCenter.default.post(name: NSNotification.Name("UpdateNode"), object: nil, userInfo: ["node": updated])
					print("🎬 handleVideoSelection: posted UpdateNode notification with updated video_url (Data path)")
				} else {
					print("❌ handleVideoSelection: Data.self loadTransferable also returned nil")
				}
			}
        } catch {
			print("❌ handleVideoSelection: error=\(error)")
        }
    }
    
    private func guessVideoMimeType(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return nil
        }
    }
    
	private func generateThumbnail(from url: URL) async -> UIImage? {
		print("🧩 generateThumbnail: start for url=\(url)")
        let asset = AVURLAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, error in
                if let cgImage, result == .succeeded {
                    print("🧩 generateThumbnail: success")
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    print("❌ generateThumbnail: error=\(String(describing: error)) result=\(result)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension VideoUploadNodeView {
    private func resolveVideoURL() -> URL? {
        let savedURLString = node.getArg("/video_url", as: String.self) ?? ""
        guard !savedURLString.isEmpty, let url = URL(string: savedURLString) else { return nil }
        return url
    }

    private func computeVideoInfo(from url: URL) async {
        let asset = AVURLAsset(url: url)
        var size: CGSize? = nil
        if let tracks = try? await asset.load(.tracks) {
            for track in tracks {
                if track.mediaType == .video {
                    size = try? await track.load(.naturalSize)
                    break
                }
            }
        }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        let resText: String?
        if let s = size {
            resText = "\(Int(max(s.width, 1)))×\(Int(max(s.height, 1)))"
        } else {
            resText = nil
        }
        await MainActor.run {
            self.videoResolutionText = resText
            self.videoFileSizeText = sizeText
        }
    }
}

extension ImageUploadNodeView {
    private func computeImageInfo(from url: URL) async {
        let res: String?
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
           let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            res = "\(Int(w))×\(Int(h))"
        } else {
            res = nil
        }
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let sizeText = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        await MainActor.run {
            self.imageResolutionText = res
            self.imageFileSizeText = sizeText
        }
    }
}

// MARK: - Execution Status Indicator

struct ExecutionStatusIndicator: View {
    let run: Run
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: run.status.iconName)
                .font(.caption2)
                .foregroundColor(statusColor)
            
            if run.status == .running {
                ProgressView()
                    .scaleEffect(0.6)
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.1))
        .cornerRadius(8)
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
}

// MARK: - Latest Outputs View

struct LatestOutputsView: View {
    let nodeID: UUID
    let node: Node
    let onTap: (() -> Void)?
    
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    
    var body: some View {
        let latestOutputs = executionEngine.getLatestOutputsForNode(nodeID)
        let latestRun = executionEngine.getLatestRunForNode(nodeID)
        let (progress, status) = progressInfo(run: latestRun)
        
        Group {
            if !latestOutputs.isEmpty, let run = latestRun, run.status == .succeeded {
                VStack(alignment: .leading, spacing: 4) {
                    // Display primary output
                    if let primaryOutput = executionEngine.getLatestPrimaryOutputForNode(nodeID) {
                        let promptHint = node.getArg("/prompt", as: String.self)
                        InlineOutputPreviewView(artifact: primaryOutput, promptHint: promptHint, availableWidth: 212)
                    }
                }
            } else if status == .running || status == .queued {
                // VStack(alignment: .leading, spacing: 8) {
                //     HStack(spacing: 8) {
                //         ProgressView(value: (progress ?? 0) / 100.0)
                //             .progressViewStyle(LinearProgressViewStyle())
                //             .frame(maxWidth: .infinity)
                //         Text(progressText(progress: progress, status: status))
                //             .font(.caption)
                //             .foregroundStyle(.secondary)
                //     }
                // }
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(height: 100)
                    .overlay(
                        VStack(spacing: 8) {
                            Text(progressText(progress: progress, status: status))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView(value: (progress ?? 0) / 100.0)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(maxWidth: 100)
                        }
                        .padding(8)
                    )
            } else if shouldShowPlaceholder {
                // Show placeholder for executable nodes that expect image/text output but have no runs
                OutputPlaceholderView(nodeKind: node.kind)
            }
        }
        .onAppear {
            print("🔍 LatestOutputsView - NodeID: \(nodeID)")
            print("🔍 LatestOutputsView - Latest outputs count: \(latestOutputs.count)")
            print("🔍 LatestOutputsView - Latest run: \(latestRun?.id.uuidString ?? "nil")")
            print("🔍 LatestOutputsView - Latest run status: \(latestRun?.status.rawValue ?? "nil")")
            for (index, output) in latestOutputs.enumerated() {
                print("🔍 LatestOutputsView - Output \(index): \(output.displayName), URI: \(output.uri), Kind: \(output.kind)")
            }
        }
        .onTapGesture {
            // Only trigger if we have outputs to show and a callback is provided
            if !latestOutputs.isEmpty, let onTap = onTap {
                onTap()
            }
        }
    }
    
    private var shouldShowPlaceholder: Bool {
        // Only show placeholder for executable nodes that are expected to output images or text or video
        guard node.kind.isExecutable else { return false }
        
        // Check if this node type typically outputs images or text
        switch node.kind {
        case .imageGeneration, .imageEdit:
            return true
        case .videoGeneration:
            return true
        default:
            // For other executable nodes, check if they have output ports that expect images or text
            return node.ports.contains { port in
                port.direction == "out" && (
                    port.dtype == .image || port.dtype == .string || port.dtype == .video)
            }
        }
    }
    
    private func progressInfo(run: Run?) -> (Double?, RunStatus) {
        guard let run = run else { return (nil, .failed) }
        // Try to read /progress from outputsMeta or adapterDebug
        if let outputs = run.outputsMeta {
            let pointer = JSONPointer("/progress")
            if let v = pointer.get(from: outputs) {
                switch v {
                case .number(let n): return (n, run.status)
                case .string(let s): return (Double(s), run.status)
                default: break
                }
            }
        }
        if let meta = run.adapterDebug {
            let pointer = JSONPointer("/progress")
            if let v = pointer.get(from: meta) {
                switch v {
                case .number(let n): return (n, run.status)
                case .string(let s): return (Double(s), run.status)
                default: break
                }
            }
        }
        return (nil, run.status)
    }
    
    private func progressText(progress: Double?, status: RunStatus) -> String {
        if let p = progress {
            return String(format: "%@ %.1f%%", status.displayName, p)
        }
        return status.displayName
    }
}

// MARK: - Output Preview View

struct InlineOutputPreviewView: View {
    let artifact: Artifact
    let promptHint: String?
    let availableWidth: CGFloat
    
    var body: some View {
        Group {
            if artifact.isImage {
                ImagePreviewView(artifact: artifact, promptHint: promptHint, availableWidth: availableWidth)
            } else if artifact.isVideo {
                VideoPreviewView(artifact: artifact, availableWidth: availableWidth)
            } else if artifact.isText {
                TextPreviewView(artifact: artifact)
            } else {
                GenericPreviewView(artifact: artifact)
            }
        }
    }
}

struct ImagePreviewView: View {
    let artifact: Artifact
    let promptHint: String?
    let availableWidth: CGFloat
    
    @State private var imageSize: CGSize?
    
    private var calculatedHeight: CGFloat {
        if let imageSize = imageSize {
            let imageAspectRatio = imageSize.width / imageSize.height
            let calculatedHeight = availableWidth / imageAspectRatio
            
            // Limit height to reasonable bounds
            let minHeight: CGFloat = 80
            let maxHeight: CGFloat = 400
            
            let finalHeight = max(minHeight, min(maxHeight, calculatedHeight))
            print("🖼️ ImagePreviewView - Calculated height: \(finalHeight) (from \(imageSize), aspect ratio: \(imageAspectRatio), available width: \(availableWidth))")
            return finalHeight
        }
        
        // Default height when image size is not yet loaded
        print("🖼️ ImagePreviewView - Using default height: 160 (no image size yet)")
        return 160
    }
    
    var body: some View {
        Group {
            if artifact.uri == "asset://image" {
                // Temporary dummy logic: choose cat or dog asset by prompt
                let isCat = promptHint?.lowercased().contains("cat") == true
                Image(isCat ? "cat" : "dog")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: availableWidth, height: calculatedHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // Display actual saved image artifact if we have a local file URL
                if let url = ArtifactManager.shared.getArtifactURL(artifact) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            GeometryReader { geometry in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: availableWidth, height: calculatedHeight)
                                    .onAppear {
                                        // Use the artifact's size if available, otherwise use a reasonable default
                                        if let artifactSize = artifact.sizePx {
                                            print("🖼️ ImagePreviewView - Using artifact size: \(artifactSize)")
                                            self.imageSize = artifactSize
                                        } else {
                                            // Default to square aspect ratio for unknown images
                                            print("🖼️ ImagePreviewView - Using default square size")
                                            self.imageSize = CGSize(width: 512, height: 512)
                                        }
                                    }
                            }
                            .frame(width: availableWidth, height: calculatedHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        case .failure(_):
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(.systemGray6))
                                .frame(height: 160) // Constrain failure state height
                                .overlay(
                                    VStack(spacing: 2) {
                                        Image(systemName: "photo")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("Failed to load image")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                )
                        case .empty:
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(.systemGray6))
                                .frame(height: 160) // Constrain loading state height
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    // Fallback if we cannot resolve a URL
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(.systemGray6))
                        .frame(height: 160) // Constrain fallback state height
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: "photo")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(artifact.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        )
                }
            }
        }
        .onAppear {
            print("🖼️ ImagePreviewView - Artifact: \(artifact.displayName)")
            print("🖼️ ImagePreviewView - URI: \(artifact.uri)")
            print("🖼️ ImagePreviewView - Kind: \(artifact.kind)")
            print("🖼️ ImagePreviewView - MIME: \(artifact.mimeType)")
            print("🖼️ ImagePreviewView - Storage: \(artifact.storage)")
            if let url = ArtifactManager.shared.getArtifactURL(artifact) {
                print("🖼️ ImagePreviewView - Resolved URL: \(url)")
                print("🖼️ ImagePreviewView - File exists: \(FileManager.default.fileExists(atPath: url.path))")
            } else {
                print("🖼️ ImagePreviewView - Could not resolve URL")
            }
        }
    }
    
    
    private func aspectRatioModeForCard() -> ContentMode {
        // If we have the actual image size, determine the best content mode
        if let imageSize = imageSize {
            let imageAspectRatio = imageSize.width / imageSize.height
            
            // For very tall images (taller than 9:16), use fit to show the full image
            let maxAspectRatio: CGFloat = 9.0 / 16.0
            if imageAspectRatio < maxAspectRatio {
                return .fit
            }
            
            // For other images, use cover to fill the available space nicely
            return .fill
        }
        
        // Default to fit if we don't know the image dimensions
        return .fit
    }   
}

struct TextPreviewView: View {
    let artifact: Artifact
    
    var body: some View {
        Group {
            if artifact.uri.hasPrefix("data:text/plain;base64,") {
                // Extract and display the actual text content
                let base64String = String(artifact.uri.dropFirst("data:text/plain;base64,".count))
                if let data = Data(base64Encoded: base64String),
                   let textContent = String(data: data, encoding: .utf8) {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(textContent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                } else {
                    // Fallback if base64 decoding fails
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Text output")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
            } else {
                // Fallback for other text artifacts
                HStack {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(artifact.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .cornerRadius(6)
            }
        }
    }
}

struct GenericPreviewView: View {
    let artifact: Artifact
    
    var body: some View {
        HStack {
            Image(systemName: artifact.iconName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(artifact.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

// MARK: - Video Preview (first frame thumbnail)

struct VideoPreviewView: View {
    let artifact: Artifact
    let availableWidth: CGFloat
    
    @State private var thumbnail: UIImage?
    
    private var calculatedHeight: CGFloat {
        // Use a 16:9 default for video thumbnails
        let height = availableWidth * 9.0 / 16.0
        let minHeight: CGFloat = 80
        let maxHeight: CGFloat = 400
        return max(minHeight, min(maxHeight, height))
    }
    
    var body: some View {
        Group {
            if let image = thumbnail {
                ZStack(alignment: .center) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: availableWidth, height: calculatedHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                    // Play overlay
                    Circle()
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 42, height: 42)
                        .overlay(
                            Image(systemName: "play.fill")
                                .foregroundStyle(.white)
                        )
                }
            } else {
                // Placeholder while generating thumbnail
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(.systemGray6))
                    .frame(height: calculatedHeight)
                    .overlay(
                        HStack(spacing: 6) {
                            Image(systemName: "video")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(artifact.displayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                    )
            }
        }
        .onAppear(perform: loadThumbnail)
    }
    
    private func loadThumbnail() {
        guard let url = ArtifactManager.shared.getArtifactURL(artifact) else { return }
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, result, _ in
            if let cgImage, result == .succeeded {
                let uiImage = UIImage(cgImage: cgImage)
                DispatchQueue.main.async { self.thumbnail = uiImage }
            }
        }
    }
}

// MARK: - Output Placeholder View

struct OutputPlaceholderView: View {
    let nodeKind: NodeKind
    
    var body: some View {
        Group {
            if isImageOutputNode {
                ImagePlaceholderView()
            } else if isTextOutputNode {
                TextPlaceholderView()
            } else if isVideoOutputNode {
                VideoPlaceholderView()
            } else {
                GenericPlaceholderView()
            }
        }
    }
    
    private var isImageOutputNode: Bool {
        switch nodeKind {
        case .imageGeneration, .imageEdit, .seedreamEdit:
            return true
        default:
            return false
        }
    }

    private var isVideoOutputNode: Bool {
        switch nodeKind {
        case .videoGeneration:
            return true
        default:
            return false
        }
    }
    
    private var isTextOutputNode: Bool {
        // For now, we don't have specific text output nodes, but this could be expanded
        return false
    }
}

struct ImagePlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.systemGray5))
            .frame(height: 120)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No output yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            )
    }
}

struct TextPlaceholderView: View {
    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("No output yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(6)
    }
}

struct VideoPlaceholderView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(.systemGray5))
            .frame(height: 120)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "video")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No output yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            )
    }
}

struct GenericPlaceholderView: View {
    var body: some View {
        HStack {
            Image(systemName: "circle.dashed")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("No output yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(6)
    }
}


