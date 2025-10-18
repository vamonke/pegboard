import Foundation
import CoreGraphics

// MARK: - New Core Data Types

// Data types for ports
public enum DType: String, CaseIterable, Codable {
    case string
    case image
    case video
    case json
    case number
    case bool
    
    public var displayName: String {
        switch self {
        case .string: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .json: return "JSON"
        case .number: return "Number"
        case .bool: return "Boolean"
        }
    }
    
    public var iconName: String {
        switch self {
        case .string: return "character"
        case .image: return "photo"
        case .video: return "video"
        case .json: return "curlybraces"
        case .number: return "number"
        case .bool: return "checkmark.circle"
        }
    }
}

// Port definition for nodes
public struct PortDef: Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let dtype: DType
    public let direction: String // "in" or "out"
    public let mimeType: String?
    
    public init(id: UUID = UUID(), name: String, dtype: DType, direction: String, mimeType: String? = nil) {
        self.id = id
        self.name = name
        self.dtype = dtype
        self.direction = direction
        self.mimeType = mimeType
    }
}

// Node categories for execution logic
public enum NodeCategory: String, Codable, CaseIterable {
    case input = "input"           // Input nodes - no execution, just pass-through
    case execution = "execution"   // Execution nodes - require actual processing
    case output = "output"         // Output nodes - may or may not need execution
    
    public var displayName: String {
        switch self {
        case .input: return "Input"
        case .execution: return "Execution"
        case .output: return "Output"
        }
    }
}

// Flexible node kind system
public struct NodeKind: RawRepresentable, Codable, Hashable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    // Predefined node kinds
    public static let textPrompt = NodeKind(rawValue: "text_prompt")
    public static let imageGeneration = NodeKind(rawValue: "image_generation")
    public static let imageEdit = NodeKind(rawValue: "image_edit")
    public static let seedreamEdit = NodeKind(rawValue: "seedream_edit")
    public static let videoGeneration = NodeKind(rawValue: "video_generation")
    public static let imageToVideo = NodeKind(rawValue: "image_to_video")
    public static let imageUpload = NodeKind(rawValue: "image_upload")
    public static let videoUpload = NodeKind(rawValue: "video_upload")
    public static let wanAnimateMove = NodeKind(rawValue: "wan_animate_move")
    public static let wanAnimateReplace = NodeKind(rawValue: "wan_animate_replace")
    
    // Node category determines execution behavior
    public var category: NodeCategory {
        switch self {
        case .textPrompt:
            return .input
        case .imageUpload, .videoUpload:
            return .input
        case .imageGeneration:
            return .execution
        case .imageEdit, .seedreamEdit:
            return .execution
        default:
            // Default categorization based on naming patterns
            if rawValue.contains("input") || rawValue.contains("prompt") {
                return .input
            } else if rawValue.contains("generation") || rawValue.contains("generate") || rawValue.contains("process") {
                return .execution
            } else if rawValue.contains("output") || rawValue.contains("save") {
                return .output
            } else {
                return .execution // Default to execution for unknown types
            }
        }
    }
    
    // Whether this node type requires execution (calls adapters, creates runs, etc.)
    public var isExecutable: Bool {
        return category == .execution
    }
    
    // Whether this node type is an input node (just passes values through)
    public var isInputNode: Bool {
        return category == .input
    }
    
    public var displayName: String {
        switch self {
        case .textPrompt: return "Prompt"
        case .imageGeneration: return "Flux - Schnell"
        case .imageEdit: return "Nano Banana - Edit"
        case .seedreamEdit: return "SeedDream v4 - Edit"
        case .videoGeneration: return "OpenAI - Sora 2"
        case .imageToVideo: return "Kling - Image to Video"
        case .imageUpload: return "Image"
        case .videoUpload: return "Video"
        case .wanAnimateMove: return "WAN - Animate Move"
        case .wanAnimateReplace: return "WAN - Animate Replace"
        default: return rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    public var iconName: String {
        switch self {
        case .textPrompt: return "character"
        case .imageGeneration: return "photo"
        case .imageEdit: return "photo"
        case .seedreamEdit: return "photo"
        case .videoGeneration: return "film"
        case .imageToVideo: return "film"
        case .imageUpload: return "photo"
        case .videoUpload: return "film"
        case .wanAnimateMove: return "film"
        case .wanAnimateReplace: return "film"
        default: return "circle"
        }
    }
}

// JSON Value type for flexible args
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if container.decodeNil() {
            self = .null
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid JSONValue"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - JSON Pointer System

// JSON Pointer implementation for targeting specific fields in args
public struct JSONPointer {
    public let path: String
    
    public init(_ path: String) {
        self.path = path
    }
    
    // Get value from JSONValue using pointer
    public func get(from json: JSONValue) -> JSONValue? {
        let components = path.components(separatedBy: "/").dropFirst() // Remove leading "/"
        var current = json
        
        for component in components {
            switch current {
            case .object(let dict):
                if let next = dict[component] {
                    current = next
                } else {
                    return nil
                }
            case .array(let arr):
                if let index = Int(component), index < arr.count {
                    current = arr[index]
                } else {
                    return nil
                }
            default:
                return nil
            }
        }
        
        return current
    }
    
    // Set value in JSONValue using path
    public func set(_ value: JSONValue, in json: inout JSONValue) {
        let components = path.components(separatedBy: "/").dropFirst()
        
        // Helper function to set value recursively
        func setValue(at pathComponents: [String], in current: inout JSONValue) -> Bool {
            guard let component = pathComponents.first else { return false }
            let remaining = Array(pathComponents.dropFirst())
            let isLast = remaining.isEmpty
            
            switch current {
            case .object(var dict):
                if isLast {
                    dict[component] = value
                    current = .object(dict)
                    return true
                } else {
                    // Descend into the child at this component, creating an object if missing
                    var child = dict[component] ?? .object([:])
                    let didSet = setValue(at: remaining, in: &child)
                    dict[component] = child
                    current = .object(dict)
                    return didSet
                }
            case .array(var arr):
                if let arrayIndex = Int(component) {
                    if isLast {
                        if arrayIndex < arr.count {
                            arr[arrayIndex] = value
                        } else {
                            // Extend array if needed
                            while arr.count <= arrayIndex {
                                arr.append(.null)
                            }
                            arr[arrayIndex] = value
                        }
                        current = .array(arr)
                        return true
                    } else {
                        if arrayIndex < arr.count {
                            current = arr[arrayIndex]
                            return setValue(at: remaining, in: &current)
                        } else {
                            return false // Can't navigate into non-existent array element
                        }
                    }
                } else {
                    return false // Invalid array index
                }
            default:
                return false // Can't set in non-object/non-array
            }
        }
        
        _ = setValue(at: Array(components), in: &json)
    }
}

// MARK: - Binding System

// Binding connects a source port to a target node's arg path
public struct Binding: Codable, Identifiable {
    public let id: UUID
    public let sourcePortID: UUID
    public let targetNodeID: UUID
    public let argPath: String // JSON Pointer path
    
    public init(id: UUID = UUID(), sourcePortID: UUID, targetNodeID: UUID, argPath: String) {
        self.id = id
        self.sourcePortID = sourcePortID
        self.targetNodeID = targetNodeID
        self.argPath = argPath
    }
}

// MARK: - Core Graph Structures

public struct NodeID: Hashable, Codable {
    public var raw: UUID
    public init(raw: UUID = UUID()) { self.raw = raw }
}

public struct EdgeID: Hashable, Codable {
    public var raw: UUID
    public init(raw: UUID = UUID()) { self.raw = raw }
}

// Connection point on a node
public struct ConnectionPoint: Hashable, Codable {
    public var nodeID: NodeID
    public var portID: UUID
    public var position: CGPoint // relative to node center
    
    public init(nodeID: NodeID, portID: UUID, position: CGPoint) {
        self.nodeID = nodeID
        self.portID = portID
        self.position = position
    }
}

// Edge connecting two nodes
public struct Edge: Identifiable, Codable {
    public var id: EdgeID
    public var source: ConnectionPoint
    public var target: ConnectionPoint
    
    public init(id: EdgeID = EdgeID(), source: ConnectionPoint, target: ConnectionPoint) {
        self.id = id
        self.source = source
        self.target = target
    }
}

// MARK: - Node Structure

public struct Node: Identifiable, Codable {
    public let id: UUID
    public let kind: NodeKind
    public var frame: CGRect
    public var schemaVersion: Int
    public var args: JSONValue
    public var uiState: JSONValue?
    public var ports: [PortDef]
    
    public init(id: UUID = UUID(), kind: NodeKind, frame: CGRect, schemaVersion: Int = 1, args: JSONValue = .object([:]), uiState: JSONValue? = nil, ports: [PortDef] = []) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.schemaVersion = schemaVersion
        self.args = args
        self.uiState = uiState
        self.ports = ports
    }
    
    // Helper methods for working with args
    public func getArg<T>(_ path: String, as type: T.Type) -> T? {
        let pointer = JSONPointer(path)
        guard let value = pointer.get(from: args) else { return nil }
        
        switch (value, type) {
        case (.string(let str), is String.Type):
            return str as? T
        case (.number(let num), is Double.Type):
            return num as? T
        case (.number(let num), is Int.Type):
            return Int(num) as? T
        case (.bool(let bool), is Bool.Type):
            return bool as? T
        default:
            return nil
        }
    }
    
    public mutating func setArg<T>(_ path: String, value: T) {
        let pointer = JSONPointer(path)
        let jsonValue: JSONValue
        
        switch value {
        case let str as String:
            jsonValue = .string(str)
        case let num as Double:
            jsonValue = .number(num)
        case let num as Int:
            jsonValue = .number(Double(num))
        case let bool as Bool:
            jsonValue = .bool(bool)
        default:
            return // Unsupported type
        }
        
        pointer.set(jsonValue, in: &args)
    }
}


// Centralized argPath resolution for target input ports
public extension Node {
    func argPath(for targetPort: PortDef) -> String {
        switch kind {
        case .textPrompt:
            return "/text"
        case .imageGeneration:
            switch targetPort.name {
            case "prompt": return "/prompt"
            default: return "/\(targetPort.name)"
            }
        case .imageEdit:
            switch targetPort.name {
            case "prompt": return "/prompt"
            case "image_urls": return "/image_urls"
            default: return "/\(targetPort.name)"
            }
        case .seedreamEdit:
            switch targetPort.name {
            case "prompt": return "/prompt"
            case "image_urls": return "/image_urls"
            default: return "/\(targetPort.name)"
            }
        case .videoGeneration:
            switch targetPort.name {
            case "prompt": return "/prompt"
            case "input_reference": return "/input_reference"
            default: return "/\(targetPort.name)"
            }
        case .imageToVideo:
            switch targetPort.name {
            case "prompt": return "/prompt"
            case "image_url": return "/image_url"
            default: return "/\(targetPort.name)"
            }
        case .wanAnimateMove:
            switch targetPort.name {
            case "video_url": return "/video_url"
            case "image_url": return "/image_url"
            default: return "/\(targetPort.name)"
            }
        case .wanAnimateReplace:
            switch targetPort.name {
            case "video_url": return "/video_url"
            case "image_url": return "/image_url"
            default: return "/\(targetPort.name)"
            }
        default:
            return "/\(targetPort.name)"
        }
    }
}


public struct Viewport: Codable, Equatable {
    public var scale: CGFloat
    public var offset: CGSize

    public init(scale: CGFloat = 1.0, offset: CGSize = .zero) {
        self.scale = scale
        self.offset = offset
    }

    public static let identity = Viewport()

    public func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width,
                y: point.y * scale + offset.height)
    }

    public func screenToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale,
                y: (point.y - offset.height) / scale)
    }

    public mutating func zoomAroundScreenPoint(relativeScale: CGFloat, anchorScreen: CGPoint, minScale: CGFloat = 0.4, maxScale: CGFloat = 3.0) {
        let startScale = scale
        let clampedScale = max(min(startScale * relativeScale, maxScale), minScale)
        let worldAtAnchorBefore = CGPoint(
            x: (anchorScreen.x - offset.width) / startScale,
            y: (anchorScreen.y - offset.height) / startScale
        )
        offset = CGSize(
            width: anchorScreen.x - worldAtAnchorBefore.x * clampedScale,
            height: anchorScreen.y - worldAtAnchorBefore.y * clampedScale
        )
        scale = clampedScale
    }
}

// MARK: - Graph Structure

public struct Graph: Codable {
    public let id: UUID
    public var nodes: [UUID: Node]
    public var bindings: [UUID: Binding]
    public var edges: [UUID: Edge] // Visual edges only
    public var selectedEdgeID: EdgeID? // Track selected edge
    public var viewport: Viewport
    public let graphVersion: Int
    public let updatedAt: Date
    
    public init(id: UUID = UUID(), nodes: [UUID: Node] = [:], bindings: [UUID: Binding] = [:], edges: [UUID: Edge] = [:], selectedEdgeID: EdgeID? = nil, viewport: Viewport = .identity, graphVersion: Int = 2, updatedAt: Date = Date()) {
        self.id = id
        self.nodes = nodes
        self.bindings = bindings
        self.edges = edges
        self.selectedEdgeID = selectedEdgeID
        self.viewport = viewport
        self.graphVersion = graphVersion
        self.updatedAt = updatedAt
    }
    
    // MARK: - Binding Management
    
    public mutating func addBinding(sourcePortID: UUID, targetNodeID: UUID, argPath: String) {
        let binding = Binding(sourcePortID: sourcePortID, targetNodeID: targetNodeID, argPath: argPath)
        bindings[binding.id] = binding
    }
    
    public mutating func removeBinding(_ bindingID: UUID) {
        bindings.removeValue(forKey: bindingID)
    }
    
    public func getBindingsForNode(_ nodeID: UUID) -> [Binding] {
        return bindings.values.filter { $0.targetNodeID == nodeID }
    }
    
    // MARK: - Edge Management
    
    public mutating func selectEdge(_ edgeID: EdgeID) {
        selectedEdgeID = edgeID
    }
    
    public mutating func deselectEdge() {
        selectedEdgeID = nil
    }
    
    public mutating func removeEdge(_ edgeID: EdgeID) {
        edges.removeValue(forKey: edgeID.raw)
        // Deselect if this edge was selected
        if selectedEdgeID == edgeID {
            selectedEdgeID = nil
        }
    }
    
    public mutating func removeEdgesConnectedToNode(_ nodeID: UUID) {
        let edgesToRemove = edges.filter { edge in
            edge.value.source.nodeID.raw == nodeID || edge.value.target.nodeID.raw == nodeID
        }
        
        for edge in edgesToRemove {
            edges.removeValue(forKey: edge.key)
            // Deselect if any removed edge was selected
            if selectedEdgeID == edge.value.id {
                selectedEdgeID = nil
            }
        }
    }
    
    // MARK: - Data Flow Resolution
    
    public func resolveArgs(for nodeID: UUID) -> JSONValue {
        guard let node = nodes[nodeID] else { return .object([:]) }
        
        var resolvedArgs = node.args
        let incomingBindings = getBindingsForNode(nodeID)
        
        for binding in incomingBindings {
            // Find the source port and get its value
            guard let sourceNode = findNodeWithPort(binding.sourcePortID),
                  let sourcePort = sourceNode.ports.first(where: { $0.id == binding.sourcePortID }) else {
                continue
            }
            
            // Get the output value from the source node
            let outputValue = getOutputValue(from: sourceNode, port: sourcePort)
            
            // Apply the binding to the target args
            let pointer = JSONPointer(binding.argPath)
            
            // Special handling for image_urls: if we're binding a single image to image_urls,
            // wrap it in an array to maintain the expected array structure
            let finalValue: JSONValue
            if binding.argPath == "/image_urls", case .string = outputValue {
                finalValue = .array([outputValue])
            } else {
                finalValue = outputValue
            }
            
            pointer.set(finalValue, in: &resolvedArgs)
        }
        
        return resolvedArgs
    }
    
    private func findNodeWithPort(_ portID: UUID) -> Node? {
        return nodes.values.first { node in
            node.ports.contains { $0.id == portID }
        }
    }
    
    private func getOutputValue(from node: Node, port: PortDef) -> JSONValue {
        // Handle input nodes - they pass their input values directly
        if node.kind.isInputNode {
            return getInputNodeOutputValue(from: node, port: port)
        }
        
        // Handle execution nodes - get values from completed runs
        return getExecutionNodeOutputValue(from: node, port: port)
    }
    
    private func getInputNodeOutputValue(from node: Node, port: PortDef) -> JSONValue {
        // For input nodes, the output is just the input value
        switch node.kind {
        case .textPrompt:
            // For text prompt, return the text input directly
            let textInput = node.getArg("/text", as: String.self) ?? ""
            return .string(textInput)
        case .imageUpload:
            let url = node.getArg("/image_url", as: String.self) ?? ""
            return .string(url.isEmpty ? "image://placeholder" : url)
        case .videoUpload:
            let url = node.getArg("/video_url", as: String.self) ?? ""
            return .string(url.isEmpty ? "video://placeholder" : url)
        default:
            // For other input node types, return the appropriate input value
            switch port.dtype {
            case .string:
                return .string("Input value from \(node.kind.displayName)")
            case .number:
                return .number(42.0)
            case .bool:
                return .bool(true)
            case .json:
                return .object(["input": .bool(true)])
            default:
                return .string("input://placeholder")
            }
        }
    }
    
    private func getExecutionNodeOutputValue(from node: Node, port: PortDef) -> JSONValue {
        // For execution nodes, get values from completed runs
        // Use ExecutionEngine to get actual output values from completed runs
        let executionEngine = ExecutionEngine.shared
        
        // Get the latest run for this node
        let latestRun = executionEngine.getLatestRunForNode(node.id)
        
        if let run = latestRun, run.status == .succeeded {
            // Get the primary artifact for this run
            let primaryArtifact = executionEngine.getLatestPrimaryOutputForNode(node.id)
            
            switch port.dtype {
            case .string:
                if let artifact = primaryArtifact {
                    return .string(artifact.uri)
                }
                return .string("Generated text from \(node.kind.displayName)")
            case .image:
                if let artifact = primaryArtifact {
                    return .string(artifact.uri)
                }
                return .string("image://placeholder")
            case .video:
                if let artifact = primaryArtifact {
                    return .string(artifact.uri)
                }
                return .string("video://placeholder")
            case .json:
                return .object(["generated": .bool(true)])
            case .number:
                return .number(42.0)
            case .bool:
                return .bool(true)
            }
        } else {
            // No successful run yet, return placeholder values
            switch port.dtype {
            case .string:
                return .string("Generated text from \(node.kind.displayName)")
            case .image:
                return .string("image://placeholder")
            case .video:
                return .string("video://placeholder")
            case .json:
                return .object(["generated": .bool(true)])
            case .number:
                return .number(42.0)
            case .bool:
                return .bool(true)
            }
        }
    }
}

// MARK: - Node Factory Functions

extension Node {
    // Create a TextPrompt node with default ports and args
    public static func textPrompt(id: UUID = UUID(), frame: CGRect, text: String = "") -> Node {
        let ports = [
            PortDef(name: "text_output", dtype: .string, direction: "out")
        ]
        
        let args: JSONValue = .object([
            "text": .string(text)
        ])
        
        return Node(
            id: id,
            kind: .textPrompt,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create an ImageGeneration node with default ports and args
    public static func imageGeneration(
        id: UUID = UUID(),
        frame: CGRect,
        prompt: String = "",
        size: CGSize = CGSize(width: 512, height: 512)
    ) -> Node {
        let ports = [
            PortDef(name: "prompt", dtype: .string, direction: "in"),
            PortDef(name: "image_output", dtype: .image, direction: "out", mimeType: "image/png")
        ]
        
        let args: JSONValue = .object([
            "prompt": .string(prompt),
            "size": .object([
                "width": .number(Double(size.width)),
                "height": .number(Double(size.height))
            ])
        ])
        
        return Node(
            id: id,
            kind: .imageGeneration,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create an ImageEdit node with default ports and args
    public static func imageEdit(
        id: UUID = UUID(),
        frame: CGRect,
        prompt: String = "",
        imageUrls: [String] = [],
        numImages: Int = 1,
        outputFormat: String = "jpeg"
    ) -> Node {
        let ports = [
            PortDef(name: "prompt", dtype: .string, direction: "in"),
            PortDef(name: "image_urls", dtype: .image, direction: "in"),
            PortDef(name: "image_output", dtype: .image, direction: "out", mimeType: "image/jpeg")
        ]
        
        let args: JSONValue = .object([
            "prompt": .string(prompt),
            "image_urls": .array(imageUrls.map { .string($0) }),
            "num_images": .number(Double(numImages)),
            "output_format": .string(outputFormat)
        ])
        
        return Node(
            id: id,
            kind: .imageEdit,
            frame: frame,
            args: args,
            ports: ports
        )
    }

    // Create a SeedDream v4 Edit node with default ports and args
    public static func seedreamEdit(
        id: UUID = UUID(),
        frame: CGRect,
        prompt: String = "",
        imageUrls: [String] = [],
        numImages: Int = 1,
        imageSize: CGSize = CGSize(width: 2048, height: 2048),
        maxImages: Int = 1,
        enableSafetyChecker: Bool = true,
        seed: Int? = nil
    ) -> Node {
        let ports = [
            PortDef(name: "prompt", dtype: .string, direction: "in"),
            PortDef(name: "image_urls", dtype: .image, direction: "in"),
            PortDef(name: "image_output", dtype: .image, direction: "out", mimeType: "image/png")
        ]
        var argsObj: [String: JSONValue] = [
            "prompt": .string(prompt),
            "image_urls": .array(imageUrls.map { .string($0) }),
            "num_images": .number(Double(max(1, min(6, numImages)))) ,
            "image_size": .object([
                "width": .number(Double(imageSize.width)),
                "height": .number(Double(imageSize.height))
            ]),
            "max_images": .number(Double(max(1, min(6, maxImages)))),
            "enable_safety_checker": .bool(enableSafetyChecker)
        ]
        if let seed = seed { argsObj["seed"] = .number(Double(seed)) }
        let args: JSONValue = .object(argsObj)
        return Node(
            id: id,
            kind: .seedreamEdit,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create a VideoGeneration node with default ports and args (OpenAI Sora)
    public static func videoGeneration(
        id: UUID = UUID(),
        frame: CGRect,
        prompt: String = "",
        size: CGSize = CGSize(width: 720, height: 1280),
        seconds: Int = 4,
        model: String = "sora-2"
    ) -> Node {
        let ports = [
            PortDef(name: "prompt", dtype: .string, direction: "in"),
            PortDef(name: "input_reference", dtype: .image, direction: "in"),
            PortDef(name: "video_output", dtype: .video, direction: "out", mimeType: "video/mp4")
        ]
        
        let args: JSONValue = .object([
            "prompt": .string(prompt),
            "size": .object([
                "width": .number(Double(size.width)),
                "height": .number(Double(size.height))
            ]),
            "seconds": .number(Double(seconds)),
            "model": .string(model)
        ])
        
        return Node(
            id: id,
            kind: .videoGeneration,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create an Image->Video node (FAL Kling)
    public static func imageToVideo(
        id: UUID = UUID(),
        frame: CGRect,
        prompt: String = "",
        imageURL: String? = nil,
        duration: String = "5",
        cfgScale: Double = 0.5,
        negativePrompt: String = "blur, distort, and low quality"
    ) -> Node {
        let ports = [
            PortDef(name: "prompt", dtype: .string, direction: "in"),
            PortDef(name: "image_url", dtype: .image, direction: "in"),
            PortDef(name: "video_output", dtype: .video, direction: "out", mimeType: "video/mp4")
        ]
        
        var argsObj: [String: JSONValue] = [
            "prompt": .string(prompt),
            "duration": .string(duration),
            "cfg_scale": .number(cfgScale),
            "negative_prompt": .string(negativePrompt)
        ]
        if let imageURL = imageURL {
            argsObj["image_url"] = .string(imageURL)
        } else {
            argsObj["image_url"] = .null
        }
        
        let args: JSONValue = .object(argsObj)
        
        return Node(
            id: id,
            kind: .imageToVideo,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create a WAN Animate Move node (FAL WAN v2.2-14b)
    public static func wanAnimateMove(
        id: UUID = UUID(),
        frame: CGRect,
        resolution: String = "480p",
        seed: Int? = nil,
        numInferenceSteps: Int = 20,
        enableSafetyChecker: Bool = false,
        enableOutputSafetyChecker: Bool = false,
        shift: Double = 5.0,
        videoQuality: String = "high",
        videoWriteMode: String = "balanced"
    ) -> Node {
        let ports = [
            PortDef(name: "video_url", dtype: .video, direction: "in"),
            PortDef(name: "image_url", dtype: .image, direction: "in"),
            PortDef(name: "video_output", dtype: .video, direction: "out", mimeType: "video/mp4")
        ]

        var argsDict: [String: JSONValue] = [
            "resolution": .string(resolution),
            "num_inference_steps": .number(Double(numInferenceSteps)),
            "enable_safety_checker": .bool(enableSafetyChecker),
            "enable_output_safety_checker": .bool(enableOutputSafetyChecker),
            "shift": .number(shift),
            "video_quality": .string(videoQuality),
            "video_write_mode": .string(videoWriteMode)
        ]
        if let seed = seed { argsDict["seed"] = .number(Double(seed)) }

        let args: JSONValue = .object(argsDict)

        return Node(
            id: id,
            kind: .wanAnimateMove,
            frame: frame,
            args: args,
            ports: ports
        )
    }

    // Create a WAN Animate Replace node (FAL WAN v2.2-14b)
    public static func wanAnimateReplace(
        id: UUID = UUID(),
        frame: CGRect,
        resolution: String = "480p",
        seed: Int? = nil,
        numInferenceSteps: Int = 20,
        enableSafetyChecker: Bool = false,
        enableOutputSafetyChecker: Bool = false,
        shift: Double = 5.0,
        videoQuality: String = "high",
        videoWriteMode: String = "balanced"
    ) -> Node {
        let ports = [
            PortDef(name: "video_url", dtype: .video, direction: "in"),
            PortDef(name: "image_url", dtype: .image, direction: "in"),
            PortDef(name: "video_output", dtype: .video, direction: "out", mimeType: "video/mp4")
        ]

        var argsDict: [String: JSONValue] = [
            "resolution": .string(resolution),
            "num_inference_steps": .number(Double(numInferenceSteps)),
            "enable_safety_checker": .bool(enableSafetyChecker),
            "enable_output_safety_checker": .bool(enableOutputSafetyChecker),
            "shift": .number(shift),
            "video_quality": .string(videoQuality),
            "video_write_mode": .string(videoWriteMode)
        ]
        if let seed = seed { argsDict["seed"] = .number(Double(seed)) }

        let args: JSONValue = .object(argsDict)

        return Node(
            id: id,
            kind: .wanAnimateReplace,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create an Image Upload input node
    public static func imageUpload(
        id: UUID = UUID(),
        frame: CGRect
    ) -> Node {
        let ports = [
            PortDef(name: "image_output", dtype: .image, direction: "out")
        ]
        let args: JSONValue = .object([
            "image_url": .string("")
        ])
        return Node(
            id: id,
            kind: .imageUpload,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    // Create a Video Upload input node
    public static func videoUpload(
        id: UUID = UUID(),
        frame: CGRect
    ) -> Node {
        let ports = [
            PortDef(name: "video_output", dtype: .video, direction: "out")
        ]
        let args: JSONValue = .object([
            "video_url": .string("")
        ])
        return Node(
            id: id,
            kind: .videoUpload,
            frame: frame,
            args: args,
            ports: ports
        )
    }
    
    
}



