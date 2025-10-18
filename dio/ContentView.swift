import SwiftUI

struct ContentView: View {
    // Graph state
    @State private var graph: Graph = Graph()
    @State private var selectedNodeID: UUID?
    @State private var refreshTrigger: UUID = UUID()
    
    // Cell navigation state
    @State private var focusedCellRow: Int = 0
    @State private var focusedCellCol: Int = 0
    // Map each node to a discrete cell (row, col)
    @State private var nodeCells: [UUID: (row: Int, col: Int)] = [:]
    
    // Node interaction
    @State private var draggedNodeID: UUID?
    @State private var isDragging: Bool = false
    @State private var nodeDragOffsets: [UUID: CGSize] = [:]
    
    // Port selection
    @State private var selectedPort: PortDef?
    
    // Sheet state
    @State private var isEditSheetPresented: Bool = false
    @State private var editingNodeID: UUID?
    @State private var isNodeCreationMenuPresented: Bool = false
    @State private var isBottomSheetPresented: Bool = false
    @State private var isImageNodePagePresented: Bool = false
    @State private var selectedNodeForOutputPreview: UUID?
    @State private var editingTextPromptNodeID: UUID?
    @State private var showArtifactGallery: Bool = false
    // Add Node hierarchical menu state
    private enum AddMenuLevel {
        case root
        case upload
        case image
        case video
    }
    @State private var addMenuLevel: AddMenuLevel = .root
    
    // Execution state
    @StateObject private var executionEngine = ExecutionEngine.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var showRunHistory = false
    @State private var selectedNodeForHistory: UUID?
    @State private var executionDebounceTask: Task<Void, Never>?
    @State private var screenSize: CGSize = .zero
    @State private var nodeSizes: [UUID: CGSize] = [:]
    // Live drag offset for TikTok-like swipe feel
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                mainCanvasView(geometry: geometry)
            }
            // Top-level overlay for FAB to avoid canvas transforms
            if selectedPort == nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            addMenuLevel = .root
                            isNodeCreationMenuPresented = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 68, height: 68)
                                .background(
                                    Circle()
                                        .fill(Color.accentColor)
                                )
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
                        Spacer()
                    }
                    .padding(.bottom, 24)
                }
                .zIndex(1000)
            }
        }
    }
    
    // MARK: - Main Canvas View
    
    private func mainCanvasView(geometry: GeometryProxy) -> some View {
        let screenSize = geometry.size
        // Cell size to allow 20% peeking of neighbors
        let cellWidth = screenSize.width * 0.75
        let cellHeight = screenSize.width * 1

        return ZStack {
            // Background (kept lightweight)
            GridBackground(canvasSize: screenSize)
                .frame(width: screenSize.width, height: screenSize.height)
                .offset(x: dragOffset.width * 0.2, y: dragOffset.height * 0.2)

            // Render all edges first (so they appear behind nodes)
            edgesView(initialOffsetX: 0, initialOffsetY: 0, cellWidth: cellWidth, cellHeight: cellHeight, screenSize: screenSize)
            
            // Render all nodes in cell-based layout
            nodesViewForCells(cellWidth: cellWidth, cellHeight: cellHeight, screenSize: screenSize)
            
            // Top toolbar with execution controls
            toolbarView()

        }
        .background(Color(.systemBackground))
        .onPreferenceChange(NodeSizePreferenceKey.self) { sizes in
            nodeSizes.merge(sizes, uniquingKeysWith: { $1 })
        }
        .sheet(isPresented: SwiftUI.Binding(
            get: { editingNodeID != nil },
            set: { newValue in
                if !newValue { editingNodeID = nil }
            }
        )) {
            editSheetView()
        }
        .sheet(isPresented: SwiftUI.Binding(
            get: { editingTextPromptNodeID != nil },
            set: { newValue in
                if !newValue { editingTextPromptNodeID = nil }
            }
        )) {
            textPromptEditSheetView()
        }
        .sheet(isPresented: $isNodeCreationMenuPresented, onDismiss: {
            addMenuLevel = .root
        }) {
            nodeCreationMenuSheet()
        }
        .sheet(isPresented: $showRunHistory) {
            runHistorySheetView()
        }
        .sheet(isPresented: $isBottomSheetPresented) {
            bottomSheetView()
        }
        .sheet(isPresented: $showArtifactGallery) {
            ArtifactGalleryView(
                persistence: persistence,
                isPresented: $showArtifactGallery
            )
        }
        .fullScreenCover(isPresented: $isImageNodePagePresented) {
            imageNodePageView()
        }
        .fullScreenCover(isPresented: SwiftUI.Binding(
            get: { selectedNodeForOutputPreview != nil },
            set: { newValue in
                if !newValue { selectedNodeForOutputPreview = nil }
            }
        )) {
            outputPreviewSheetView()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            clearSelection()
        }
        .onAppear {
            // Keep track of current screen size for centering new nodes
            self.screenSize = geometry.size
            // handleOnAppear()
            
            // Listen for text prompt edit notifications
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("EditTextPrompt"),
                object: nil,
                queue: .main
            ) { notification in
                if let nodeID = notification.userInfo?["nodeID"] as? UUID {
                    editTextPrompt(nodeID)
                }
            }
            // Listen for node updates from subviews (e.g., upload nodes)
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UpdateNode"),
                object: nil,
                queue: .main
            ) { notification in
                if let updated = notification.userInfo?["node"] as? Node {
                    updateNode(updated)
                }
            }
            // Initialize nodeCells for existing nodes
            let cellWidth = geometry.size.width * 0.75
            let cellHeight = geometry.size.width * 1
            initializeNodeCellsIfNeeded(cellWidth: cellWidth, cellHeight: cellHeight)
        }
        .onChange(of: geometry.size) { oldValue, newValue in
            self.screenSize = newValue
        }
        .gesture(cellSwipeGesture())
    }
    
    // MARK: - Extracted View Components
    
    // TikTok-like swipe: continuous drag, then spring settle based on velocity/prediction
    private func cellSwipeGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let dx = value.predictedEndTranslation.width
                let dy = value.predictedEndTranslation.height
                let primaryHorizontal = abs(dx) > abs(dy)
                let threshold: CGFloat = 60

                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.2)) {
                    if primaryHorizontal {
                        if dx > threshold { focusedCellCol -= 1 }
                        else if dx < -threshold { focusedCellCol += 1 }
                    } else {
                        // Invert vertical: swipe up (dy negative) moves to next row down
                        if dy > threshold { focusedCellRow -= 1 }
                        else if dy < -threshold { focusedCellRow += 1 }
                    }
                    dragOffset = .zero
                }
            }
    }
    
    private func edgesView(
        initialOffsetX: CGFloat,
        initialOffsetY: CGFloat,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        screenSize: CGSize
    ) -> some View {
        ForEach(Array(graph.edges.values), id: \.id.raw) { edge in
            if let sourceNode = graph.nodes[edge.source.nodeID.raw],
               let targetNode = graph.nodes[edge.target.nodeID.raw] {
                
                // Calculate positions the same way as nodes
                let sourceCell = nodeCells[sourceNode.id] ?? (0, 0)
                let targetCell = nodeCells[targetNode.id] ?? (0, 0)
                let centerX = screenSize.width / 2
                let centerY = screenSize.height / 2
                
                let sourcePosition = CGPoint(
                    x: centerX + CGFloat(sourceCell.col) * cellWidth,
                    y: centerY + CGFloat(sourceCell.row) * cellHeight
                )
                let targetPosition = CGPoint(
                    x: centerX + CGFloat(targetCell.col) * cellWidth,
                    y: centerY + CGFloat(targetCell.row) * cellHeight
                )
                
                let isSelected = graph.selectedEdgeID == edge.id
                
                EdgeView(
                    edge: edge,
                    sourceNode: sourceNode,
                    targetNode: targetNode,
                    sourceScreenPosition: sourcePosition,
                    targetScreenPosition: targetPosition,
                    nodeSizes: nodeSizes,
                    isSelected: isSelected,
                    onSelect: {
                        selectEdge(edge.id)
                    },
                    onDelete: {
                        deleteEdge(edge.id)
                    }
                )
            }
        }
        .offset(
            x: -CGFloat(focusedCellCol) * cellWidth + dragOffset.width,
            y: -CGFloat(focusedCellRow) * cellHeight + dragOffset.height
        )
    }
    
    private func toolbarView() -> some View {
        VStack {
            HStack {
                HStack(spacing: 12) {
                    Button(action: { showArtifactGallery = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Gallery")
                                .font(.headline)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    if executionEngine.isExecuting {
                        Button(action: { executionEngine.cancelExecution() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                Text("Cancel")
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                    
                    // Execution status indicator
                    if executionEngine.isExecuting {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Executing...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Spacer()
        }
    }

    private func nodesViewForCells(cellWidth: CGFloat, cellHeight: CGFloat, screenSize: CGSize) -> some View {
        ForEach(Array(graph.nodes.values), id: \.id) { node in
            let connectedBindings = graph.getBindingsForNode(node.id)
            let cell = nodeCells[node.id] ?? (0, 0)
            let centerX = screenSize.width / 2
            let centerY = screenSize.height / 2
            let dx = CGFloat(cell.col - focusedCellCol) * cellWidth
            let dy = CGFloat(cell.row - focusedCellRow) * cellHeight
            let nodePosition = CGPoint(
                x: centerX + dx + dragOffset.width,
                y: centerY + dy + dragOffset.height
            )

            NodeCard(
                node: node,
                connectedBindings: connectedBindings,
                isSelected: selectedNodeID == node.id,
                onDelete: { deleteNode(node.id) },
                onPortTap: { portID in
                    handlePortTap(portID: portID)
                },
                onShowRunHistory: node.kind.isInputNode ? nil : { showRunHistoryForNode(node.id) },
                onExecuteNode: node.kind.isInputNode ? nil : { executeNode(node.id) },
                onShowOutputPreview: { showOutputPreviewForNode(node.id) },
                onCardTap: {
                    handleNodeCardTap(targetNode: node)
                },
                onEdit: {
                    editNode(node.id)
                },
                selectedPort: selectedPort
            )
            .position(x: nodePosition.x, y: nodePosition.y)
        }
        .id(refreshTrigger)
    }

    private func floatingActionBar() -> some View {
        HStack {
            Spacer()
            Button(action: {
                isNodeCreationMenuPresented = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 68, height: 68)
                    .background(
                        Circle()
                            .fill(Color.accentColor)
                    )
            }
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
            Spacer()
        }
        .padding(.vertical, 16)
        .background(.clear)
    }
    
    private func editSheetView() -> some View {
        Group {
            if let nodeID = editingNodeID,
               let node = graph.nodes[nodeID] {
                NodeEditSheet(
                    node: node,
                    isPresented: SwiftUI.Binding(
                        get: { editingNodeID != nil },
                        set: { newValue in
                            if !newValue { editingNodeID = nil }
                        }
                    ),
                    onSave: { updatedNode in
                        updateNode(updatedNode)
                    },
                    onDelete: {
                        deleteNode(node.id)
                        isEditSheetPresented = false
                    }
                )
            } else {
                VStack {
                    Text("Error: No node ID available")
                        .foregroundColor(.red)
                    Text("editingNodeID: \(editingNodeID?.uuidString ?? "nil")")
                    Button("Close") {
                        isEditSheetPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    private func textPromptEditSheetView() -> some View {
        Group {
            if let nodeID = editingTextPromptNodeID,
               let node = graph.nodes[nodeID] {
                TextPromptEditSheet(
                    node: node,
                    isPresented: SwiftUI.Binding(
                        get: { editingTextPromptNodeID != nil },
                        set: { newValue in
                            if !newValue { editingTextPromptNodeID = nil }
                        }
                    ),
                    onSave: { updatedNode in
                        updateNode(updatedNode)
                    }
                )
                .presentationDragIndicator(.visible)
                .onAppear {
                    print("Creating TextPromptEditSheet for node: \(nodeID)")
                    print("TextPromptEditSheet presenting for node: \(nodeID)")
                    print("Node text content: \(node.getArg("/text", as: String.self) ?? "nil")")
                }
            } else {
                VStack {
                    Text("Error: No node ID available")
                        .foregroundColor(.red)
                    Text("editingTextPromptNodeID: \(editingTextPromptNodeID?.uuidString ?? "nil")")
                    Button("Close") {
                        editingTextPromptNodeID = nil
                    }
                }
                .padding()
            }
        }
    }
    
    private func nodeCreationMenuSheet() -> some View {
        VStack(spacing: 16) {
            HStack {
                if addMenuLevel != .root {
                    Button(action: {
                        addMenuLevel = .root
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                }
                Spacer()
                Button("Cancel") {
                    isNodeCreationMenuPresented = false
                }
            }
            .padding(.horizontal)
            .padding(.top)

            ScrollView {
                VStack(spacing: 12) {
                    switch addMenuLevel {
                    case .root:
                        Group {
                            menuCategoryButton(icon: "square.and.arrow.up", title: "Upload") {
                                addMenuLevel = .upload
                            }
                            menuCategoryButton(icon: "photo", title: "Image") {
                                addMenuLevel = .image
                            }
                            menuCategoryButton(icon: "film", title: "Video") {
                                addMenuLevel = .video
                            }
                            menuLeafButton(icon: "character", title: "Text Prompt") {
                                addNode(of: .textPrompt, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                        }

                    case .upload:
                        Group {
                            menuLeafButton(icon: NodeKind.imageUpload.iconName, title: NodeKind.imageUpload.displayName) {
                                addNode(of: .imageUpload, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                            menuLeafButton(icon: NodeKind.videoUpload.iconName, title: NodeKind.videoUpload.displayName) {
                                addNode(of: .videoUpload, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                        }

                    case .image:
                        Group {
                            menuLeafButton(icon: NodeKind.imageGeneration.iconName, title: NodeKind.imageGeneration.displayName) {
                                addNode(of: .imageGeneration, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                            menuLeafButton(icon: NodeKind.imageEdit.iconName, title: NodeKind.imageEdit.displayName) {
                                addNode(of: .imageEdit, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                        }

                    case .video:
                        Group {
                            menuLeafButton(icon: NodeKind.videoGeneration.iconName, title: NodeKind.videoGeneration.displayName) {
                                addNode(of: .videoGeneration, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                            menuLeafButton(icon: NodeKind.imageToVideo.iconName, title: NodeKind.imageToVideo.displayName) {
                                addNode(of: .imageToVideo, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                            menuLeafButton(icon: NodeKind.wanAnimateReplace.iconName, title: NodeKind.wanAnimateReplace.displayName) {
                                addNode(of: .wanAnimateReplace, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                            menuLeafButton(icon: NodeKind.wanAnimateMove.iconName, title: NodeKind.wanAnimateMove.displayName) {
                                addNode(of: .wanAnimateMove, at: canvasCenterPosition())
                                isNodeCreationMenuPresented = false
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func menuCategoryButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                   .font(.caption)
                   .foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private func menuLeafButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .foregroundColor(.primary)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func runHistorySheetView() -> some View {
        Group {
            if let nodeID = selectedNodeForHistory,
               let node = graph.nodes[nodeID] {
                RunHistorySheet(
                    node: node,
                    isPresented: $showRunHistory
                )
                .presentationDragIndicator(.visible)
            }
        }
    }
    
    private func bottomSheetView() -> some View {
        Group {
            if let nodeID = selectedNodeID,
               let node = graph.nodes[nodeID] {
                NodeBottomSheet(
                    node: node,
                    connectedBindingsCount: graph.getBindingsForNode(node.id).count,
                    onClose: deselectNode,
                    onUpdateNode: { updatedNode in
                        updateNode(updatedNode)
                    },
                    onDelete: { 
                        deleteNode(node.id)
                    }
                )
            }
        }
    }
    
    private func imageNodePageView() -> some View {
        Group {
            if let nodeID = selectedNodeID,
               let node = graph.nodes[nodeID] {
                ImageNodePageView(
                    node: node,
                    connectedBindingsCount: graph.getBindingsForNode(node.id).count,
                    onClose: {
                        // Close the sheet first, then deselect the node
                        isImageNodePagePresented = false
                        // Use a small delay to ensure the sheet is dismissed before deselecting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            deselectNode()
                        }
                    },
                    onUpdateNode: { updatedNode in
                        updateNode(updatedNode)
                    },
                    onDelete: { 
                        deleteNode(node.id)
                        // Close the sheet after deleting
                        isImageNodePagePresented = false
                    }
                )
            }
        }
    }
    
    private func outputPreviewSheetView() -> some View {
        Group {
            if let nodeID = selectedNodeForOutputPreview {
                if let node = graph.nodes[nodeID] {
                    return AnyView(OutputPreviewView(
                        node: node,
                        isPresented: SwiftUI.Binding(
                            get: { selectedNodeForOutputPreview != nil },
                            set: { newValue in
                                if !newValue { selectedNodeForOutputPreview = nil }
                            }
                        )
                    ))
                } else {
                    return AnyView(
                        VStack {
                            Text("Node not found")
                                .foregroundColor(.white)
                            Button("Back") {
                                selectedNodeForOutputPreview = nil
                            }
                            .foregroundColor(.blue)
                        }
                    )
                }
            } else {
                return AnyView(
                    VStack {
                        Text("No node selected")
                            .foregroundColor(.white)
                        Button("Back") {
                            selectedNodeForOutputPreview = nil
                        }
                        .foregroundColor(.blue)
                    }
                )
            }
        }
        .onAppear {
            print("🔧 outputPreviewSheetView appeared")
            print("🔧 selectedNodeForOutputPreview: \(selectedNodeForOutputPreview?.uuidString ?? "nil")")
        }
    }

    private func handlePortTap(portID: UUID) {
        guard let port = graph.nodes.values.flatMap({ $0.ports }).first(where: { $0.id == portID }) else { return }
        
        // If the port is already selected, deselect it
        if selectedPort?.id == portID {
            selectedPort = nil
            return
        }

        if port.direction == "out" {
            if let targetPort = selectedPort, targetPort.direction == "in" {
                // If we have a selected input port, connect
                createConnection(from: port, to: targetPort)
            } else {
                selectedPort = port
            }
        } else {
            if let sourcePort = selectedPort, sourcePort.direction == "out" {
                // If we have a selected output port, connect
                createConnection(from: sourcePort, to: port)
            } else {
                selectedPort = port
            }
        }

        // If there are no available input ports of the same type, show the Add Node sheet
        let available = getAvailableInputPorts(for: port)
        if available.isEmpty {
            DispatchQueue.main.async {
                addMenuLevel = .root
                self.isNodeCreationMenuPresented = true
            }
        }
    }

    private func handleNodeCardTap(targetNode: Node) {
        // If we're in selection mode (an output port is active), attempt to connect to this node
        guard let sourcePort = selectedPort, sourcePort.direction == "out" else { return }
        // Find a compatible input port on the tapped node
        let matchingPorts = targetNode.ports.filter { $0.direction == "in" && $0.dtype == sourcePort.dtype }
        // TODO: If multiple matching input ports exist, present selection to user
        if let targetPort = matchingPorts.first {
            createConnection(from: sourcePort, to: targetPort)
        }
    }
    
    private func getAvailableInputPorts(for sourcePort: PortDef) -> [(Node, PortDef)] {
        var availablePorts: [(Node, PortDef)] = []
        
        for (_, node) in graph.nodes {
            for port in node.ports {
                if port.direction == "in" && port.dtype == sourcePort.dtype {
                    availablePorts.append((node, port))
                }
            }
        }
        
        return availablePorts
    }

    
    // MARK: - Helper Functions for Position Calculations
    
    
    private func nodeDragGesture(node: Node, nodePosition: CGPoint) -> some Gesture {
        // Disabled for cell-based navigation
        DragGesture(minimumDistance: .infinity)
    }
    
    private func handleOnAppear() {
        // Only initialize once to prevent preview loading issues
        guard graph.nodes.isEmpty else { return }
        
        // Skip heavy initialization in preview mode
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            print("Skipping test node creation in preview mode")
            return
        }
        #endif
        
        print("ContentView onAppear - initializing test nodes")
        
        // For testing purposes, add a default nodes
        createTestNodes()
        
        // Create visual edges from existing bindings
        createEdgesFromBindings()
        
        print("Final state - nodes: \(graph.nodes.count), edges: \(graph.edges.count), bindings: \(graph.bindings.count)")
    }
    
    // MARK: - Node Management Functions
    
    private func addNode(of kind: NodeKind, at position: CGPoint) {
        let frame = CGRect(origin: position, size: CGSize(width: 240, height: 240))
        
        let node: Node
        switch kind {
        case .textPrompt:
            node = Node.textPrompt(frame: frame)
        case .imageGeneration:
            node = Node.imageGeneration(frame: frame)
        case .imageEdit:
            node = Node.imageEdit(frame: frame)
        case .videoGeneration:
            node = Node.videoGeneration(frame: frame)
        case .imageToVideo:
            node = Node.imageToVideo(frame: frame)
        case .wanAnimateMove:
            node = Node.wanAnimateMove(frame: frame)
        case .wanAnimateReplace:
            node = Node.wanAnimateReplace(frame: frame)
        case .imageUpload:
            node = Node.imageUpload(frame: frame)
        case .videoUpload:
            node = Node.videoUpload(frame: frame)
        
        default:
            // Fallback for unknown node kinds
            node = Node(kind: kind, frame: frame)
        }
        
        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.2)) {
            graph.nodes[node.id] = node
            // Place new node into an available cell, preferring the focused cell
            let targetCell = findAvailableCell(near: (focusedCellRow, focusedCellCol))
            nodeCells[node.id] = targetCell
            // Focus viewport on the newly added node
            focusedCellRow = targetCell.row
            focusedCellCol = targetCell.col
        }

        // If a source output port is selected, and the new node has a compatible input,
        // automatically create the connection.
        if let sourcePort = selectedPort, sourcePort.direction == "out" {
            if let targetPort = node.ports.first(where: { $0.direction == "in" && $0.dtype == sourcePort.dtype }) {
                createConnection(from: sourcePort, to: targetPort)
            } else {
                selectedPort = nil
            }
        }

        // Auto-open media picker for upload nodes right after creation
        if node.kind == .imageUpload || node.kind == .videoUpload {
            print("📌 addNode: will schedule AutoOpenMediaPicker for node id=\(node.id) kind=\(node.kind)")
            DispatchQueue.main.async {
                print("📌 addNode: posting AutoOpenMediaPicker (async next runloop) for node id=\(node.id)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("AutoOpenMediaPicker"),
                    object: nil,
                    userInfo: ["nodeID": node.id]
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("📌 addNode: re-posting AutoOpenMediaPicker (delayed) for node id=\(node.id)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("AutoOpenMediaPicker"),
                    object: nil,
                    userInfo: ["nodeID": node.id]
                )
            }
        }
    }
    
    private func deleteNode(_ nodeID: UUID) {
        // Remove all bindings connected to this node Image
        let bindingsToRemove = graph.bindings.values.filter { binding in
            // Check if any port of this node is involved in the binding
            guard let node = graph.nodes[nodeID] else { return false }
            let nodePortIDs = node.ports.map { $0.id }
            return binding.sourcePortID == nodePortIDs.first { $0 == binding.sourcePortID } ||
                   binding.targetNodeID == nodeID
        }
        
        for binding in bindingsToRemove {
            graph.removeBinding(binding.id)
        }
        
        // Then remove the node
        graph.nodes.removeValue(forKey: nodeID)
        nodeCells.removeValue(forKey: nodeID)
    }
    
    private func updateNode(_ node: Node) {
        graph.nodes[node.id] = node
        refreshTrigger = UUID() // Trigger view refresh
    }
    
    private func updateNodePosition(_ nodeID: UUID, by offset: CGSize) {
        // Disabled in cell-based system
    }

    private func canvasCenterPosition() -> CGPoint {
        // Center of current focused cell on screen
        return CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
    }
    
    private func editNode(_ nodeID: UUID) {
        editingNodeID = nodeID
        isEditSheetPresented = true
    }
    
    private func editTextPrompt(_ nodeID: UUID) {
        print("editTextPrompt called for nodeID: \(nodeID)")
        editingTextPromptNodeID = nodeID
        print("Set editingTextPromptNodeID to: \(editingTextPromptNodeID?.uuidString ?? "nil")")
    }
    
    
    private func deselectNode() {
        selectedNodeID = nil
        // Also clear any related state
        selectedNodeForOutputPreview = nil
        isEditSheetPresented = false
    }
    
    private func showOutputPreviewForNode(_ nodeID: UUID) {
        selectedNodeForOutputPreview = nodeID
        
        // Use DispatchQueue to ensure state updates happen in the right order
        DispatchQueue.main.async {
            self.isBottomSheetPresented = false
            self.isImageNodePagePresented = false
            self.isEditSheetPresented = false
        }
    }
    
    // MARK: - Edge Management
    
    private func selectEdge(_ edgeID: EdgeID) {
        graph.selectEdge(edgeID)
        // Deselect any selected node when selecting an edge
        if selectedNodeID != nil {
            deselectNode()
        }
    }
    
    private func deselectEdge() {
        graph.deselectEdge()
    }

    private func deselectPort() {
        selectedPort = nil
    }
    
    private func clearSelection() {
        // Clear any selected edge or node when tapping on empty canvas
        deselectEdge()
        deselectNode()
        deselectPort()
    }
    
    
    // MARK: - Execution Functions
    
    private func executeGraph() {
        // Cancel any existing debounce task
        executionDebounceTask?.cancel()
        
        // Debounce execution to prevent rapid successive calls
        executionDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            
            if !Task.isCancelled {
                await executionEngine.execute(graph: graph)
            }
        }
    }
    
    private func showRunHistoryForNode(_ nodeID: UUID) {
        selectedNodeForHistory = nodeID
        showRunHistory = true
    }
    
    private func executeNode(_ nodeID: UUID) {
        Task {
            await executionEngine.executeSingleNode(nodeID, in: graph)
        }
    }
    
    // MARK: - Connection Management Functions
    
    private func createConnection(from sourcePort: PortDef, to targetPort: PortDef) {
        // Find the source node based on the source port
        guard let sourceNode = findNodeWithPort(sourcePort.id) else { return }

        // Find the target node based on the target port
        guard let targetNode = findNodeWithPort(targetPort.id) else { return }
        
        // Enforce dtype compatibility and correct directions
        guard sourcePort.dtype == targetPort.dtype,
              sourcePort.direction == "out",
              targetPort.direction == "in" else {
            // Clear selection and do nothing if incompatible
            selectedPort = nil
            return
        }

        // Determine the arg path for the target port
        let argPath = targetNode.argPath(for: targetPort)
        
        // If a binding already exists for this exact connection, do nothing
        let hasExistingBinding = graph.bindings.values.contains {
            $0.sourcePortID == sourcePort.id &&
            $0.targetNodeID == targetNode.id &&
            $0.argPath == argPath
        }
        if hasExistingBinding {
            // Always clear selection even if no new connection is made
            selectedPort = nil
            return
        }

        // Create a binding
        graph.addBinding(
            sourcePortID: sourcePort.id,
            targetNodeID: targetNode.id,
            argPath: argPath
        )
        
        // Create a visual edge
        let sourceConnectionPoint = ConnectionPoint(
            nodeID: NodeID(raw: sourceNode.id),
            portID: sourcePort.id,
            position: CGPoint(x: 0, y: 0) // Relative to node center, EdgeView handles positioning
        )
        let targetConnectionPoint = ConnectionPoint(
            nodeID: NodeID(raw: targetNode.id),
            portID: targetPort.id,
            position: CGPoint(x: 0, y: 0) // Relative to node center, EdgeView handles positioning
        )
        let edge = Edge(source: sourceConnectionPoint, target: targetConnectionPoint)
        graph.edges[edge.id.raw] = edge
        
        // Clear the selection state
        selectedPort = nil
    }
    
    private func deleteBinding(_ bindingID: UUID) {
        graph.removeBinding(bindingID)
    }
    
    private func deleteEdge(_ edgeID: EdgeID) {
        // Remove any associated binding BEFORE removing the visual edge, since we need the edge info
        if let edge = graph.edges[edgeID.raw] {
            let bindingsToRemove = graph.bindings.values.filter { binding in
                // Match binding by source port and target node. Arg path may vary by port name; we clear all for this connection.
                binding.sourcePortID == edge.source.portID && binding.targetNodeID == edge.target.nodeID.raw
            }
            for binding in bindingsToRemove {
                graph.removeBinding(binding.id)
            }
        }
        
        // Now remove the visual edge
        graph.removeEdge(edgeID)
    }
    
    
    // MARK: - Helper Functions
    
    private func createEdgesFromBindings() {
         graph.edges.removeAll()
        
        print("Bindings:", graph.bindings)
        
        // Create visual edges from existing bindings
        for binding in graph.bindings.values {
            // Find the source node and port
            guard let sourceNode = findNodeWithPort(binding.sourcePortID),
                  let sourcePort = sourceNode.ports.first(where: { $0.id == binding.sourcePortID }),
                  let targetNode = graph.nodes[binding.targetNodeID] else {
                continue
            }
            
            // Find the target port based on the arg path
            let targetPortName = binding.argPath.replacingOccurrences(of: "/", with: "")
            print("Target port name:", targetPortName)
            guard let targetPort = targetNode.ports.first(where: { $0.name == targetPortName }) else {
                print("Failed to find target port for binding:", binding)
                continue
            }
            
            // Create visual edge with proper positioning
            let sourceConnectionPoint = ConnectionPoint(
                nodeID: NodeID(raw: sourceNode.id),
                portID: sourcePort.id,
                position: CGPoint(x: 0, y: 0) // Relative to node center, EdgeView handles positioning
            )
            let targetConnectionPoint = ConnectionPoint(
                nodeID: NodeID(raw: targetNode.id),
                portID: targetPort.id,
                position: CGPoint(x: 0, y: 0) // Relative to node center, EdgeView handles positioning
            )
            let edge = Edge(source: sourceConnectionPoint, target: targetConnectionPoint)
            graph.edges[edge.id.raw] = edge
            
            print("Created edge from binding: \(sourcePort.name) -> \(targetPort.name)")
        }
    }
    
    private func findNodeWithPort(_ portID: UUID) -> Node? {
        return graph.nodes.values.first { node in
            node.ports.contains { $0.id == portID }
        }
    }
    
    private func createTestNodes() {
        print("Adding default nodes...")

        addNode(of: .textPrompt, at: CGPoint(x: 200, y: 200))
        addNode(of: .imageGeneration, at: CGPoint(x: 200, y: 500))
        addNode(of: .imageEdit, at: CGPoint(x: 500, y: 500))

        print("After adding nodes - nodes count: \(graph.nodes.count)")

        // Find the text prompt and image generation nodes
        let textPromptNode = graph.nodes.values.first { $0.kind == .textPrompt }
        let imageGenNode = graph.nodes.values.first { $0.kind == .imageGeneration }
        let imageEditNode = graph.nodes.values.first { $0.kind == .imageEdit }
        
        guard let textNode = textPromptNode,
              let imageNode = imageGenNode,
              let editNode = imageEditNode else { 
            return 
        }
        
        // Find the output port of the text prompt
        let textOutputPort = textNode.ports.first { $0.direction == "out" && $0.dtype == .string }
        
        // Find the output port of the image generation
        let imageOutputPort = imageNode.ports.first { $0.direction == "out" && $0.dtype == .image }
        
        // Find the input port of the image edit
        let editInputPort = editNode.ports.first { $0.direction == "in" && $0.dtype == .image }
        
        guard let textOutput = textOutputPort,
              let imageOutput = imageOutputPort,
              let _ = editInputPort else {
            return 
        }
        
        // Create a binding from text prompt to image generation
        graph.addBinding(
            sourcePortID: textOutput.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        // Create a binding from image generation to image edit
        graph.addBinding(
            sourcePortID: imageOutput.id,
            targetNodeID: editNode.id,
            argPath: "/image_urls"
        )

        print("Created binding from \(textOutput.name) to \(imageNode.kind)")
        print("Created binding from \(imageOutput.name) to \(editNode.kind)")
    }
}


#Preview {
    ContentView()
}

// MARK: - Cell helpers
extension ContentView {
    private func initializeNodeCellsIfNeeded(cellWidth: CGFloat, cellHeight: CGFloat) {
        guard nodeCells.isEmpty else { return }
        for node in graph.nodes.values {
            let rowCol = deriveCell(fromPoint: node.frame.origin, cellWidth: cellWidth, cellHeight: cellHeight)
            if nodeCells.values.contains(where: { $0.row == rowCol.row && $0.col == rowCol.col }) {
                // Collision: find nearest available
                nodeCells[node.id] = findAvailableCell(near: rowCol)
            } else {
                nodeCells[node.id] = rowCol
            }
        }
    }

    private func deriveCell(fromPoint point: CGPoint, cellWidth: CGFloat, cellHeight: CGFloat) -> (row: Int, col: Int) {
        let col = Int(floor(point.x / max(cellWidth, 1)))
        let row = Int(floor(point.y / max(cellHeight, 1)))
        return (row, col)
    }

    private func findAvailableCell(near origin: (row: Int, col: Int)) -> (row: Int, col: Int) {
        // Prefer the origin first
        if !nodeCells.values.contains(where: { $0.row == origin.row && $0.col == origin.col }) {
            return origin
        }
        // Preferred directional placement: Down, then Down-Right variants
        let preferredCandidates: [(Int, Int)] = [
            (origin.row + 1, origin.col),        // Down
            (origin.row + 1, origin.col + 1),    // Down-Right
            (origin.row + 1, origin.col + 2),    // Down-Right-Right
            (origin.row + 1, origin.col + 3),    // Down-Right-Right-Right
        ]
        for candidate in preferredCandidates {
            if !nodeCells.values.contains(where: { $0.row == candidate.0 && $0.col == candidate.1 }) {
                return (candidate.0, candidate.1)
            }
        }
        // Spiral/Manhattan ring search
        var distance = 1
        while true {
            for d in 0...distance {
                let candidates = [
                    (origin.row + d, origin.col - distance + d), // Down
                    (origin.row + distance - d, origin.col + d), // Right
                    (origin.row - distance + d, origin.col - d), // Left
                    (origin.row - d, origin.col + distance - d), // Up
                ]
                for cell in candidates {
                    if !nodeCells.values.contains(where: { $0.row == cell.0 && $0.col == cell.1 }) {
                        return (cell.0, cell.1)
                    }
                }
            }
            distance += 1
        }
        // Fallback (should be unreachable)
        // Return a far-away cell based on current distance to satisfy return requirements
        // Using origin to compute an offset cell to avoid compiler error
        // Note: This code path will never execute due to the infinite grid search above
        // but is provided to satisfy the compiler.
        // Choose an arbitrary offset
        // swiftlint:disable:next all
        return (origin.row + distance, origin.col + distance)
    }
}
