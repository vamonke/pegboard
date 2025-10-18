import Foundation
import CoreGraphics

// MARK: - Test Examples for New Graph System

class GraphCoreTests {
    
    static func testBasicNodeCreation() {
        print("=== Testing Basic Node Creation ===")
        
        // Create a text prompt node
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240),
            text: "A beautiful sunset"
        )
        
        print("Text Node created:")
        print("- ID: \(textNode.id)")
        print("- Kind: \(textNode.kind.rawValue)")
        print("- Ports: \(textNode.ports.map { "\($0.name): \($0.dtype.rawValue)" })")
        print("- Args: \(textNode.args)")
        
        // Create an image generation node
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 300, y: 0, width: 240, height: 240),
            prompt: ""
        )
        
        print("\nImage Generation Node created:")
        print("- ID: \(imageNode.id)")
        print("- Kind: \(imageNode.kind.rawValue)")
        print("- Ports: \(imageNode.ports.map { "\($0.name): \($0.dtype.rawValue)" })")
        print("- Args: \(imageNode.args)")
    }
    
    static func testJSONPointerSystem() {
        print("\n=== Testing JSON Pointer System ===")
        
        // Create a complex args object
        var args: JSONValue = .object([
            "prompt": .string("A beautiful sunset"),
            "negativePrompt": .string("blurry, low quality"),
            "sampler": .object([
                "name": .string("euler"),
                "steps": .number(20),
                "cfgScale": .number(4.0),
                "seed": .null
            ]),
            "size": .object([
                "width": .number(768),
                "height": .number(768)
            ])
        ])
        
        print("Original args: \(args)")
        
        // Test getting values
        let promptPointer = JSONPointer("/prompt")
        let stepsPointer = JSONPointer("/sampler/steps")
        let seedPointer = JSONPointer("/sampler/seed")
        
        print("Prompt: \(promptPointer.get(from: args) ?? .null)")
        print("Steps: \(stepsPointer.get(from: args) ?? .null)")
        print("Seed: \(seedPointer.get(from: args) ?? .null)")
        
        // Test setting values
        promptPointer.set(.string("A majestic mountain"), in: &args)
        stepsPointer.set(.number(30), in: &args)
        seedPointer.set(.number(12345), in: &args)
        
        print("Updated args: \(args)")
    }
    
    static func testBindingSystem() {
        print("\n=== Testing Binding System ===")
        
        // Create nodes
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240),
            text: "A beautiful sunset"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 300, y: 0, width: 240, height: 240)
        )
        
        // Create a graph
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        
        // Create a binding from text output to image prompt input
        let textOutputPort = textNode.ports.first { $0.name == "text_output" }!
        let binding = Binding(
            sourcePortID: textOutputPort.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        graph.bindings[binding.id] = binding
        
        print("Graph created with binding:")
        print("- Source: \(textNode.kind.rawValue) -> \(textOutputPort.name)")
        print("- Target: \(imageNode.kind.rawValue) -> /prompt")
        print("- Binding ID: \(binding.id)")
        
        // Test resolving args
        let resolvedArgs = graph.resolveArgs(for: imageNode.id)
        print("Resolved args for image node: \(resolvedArgs)")
    }
    
    static func testNodeArgHelpers() {
        print("\n=== Testing Node Arg Helpers ===")
        
        var node = Node.imageGeneration(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240)
        )
        
        // Test setting args
        node.setArg("/prompt", value: "A beautiful landscape")
        node.setArg("/sampler/steps", value: 25)
        node.setArg("/size/width", value: 1024)
        
        print("Node after setting args: \(node.args)")
        
        // Test getting args
        let prompt: String? = node.getArg("/prompt", as: String.self)
        let steps: Int? = node.getArg("/sampler/steps", as: Int.self)
        let width: Double? = node.getArg("/size/width", as: Double.self)
        
        print("Retrieved values:")
        print("- Prompt: \(prompt ?? "nil")")
        print("- Steps: \(steps ?? 0)")
        print("- Width: \(width ?? 0)")
    }
    
    static func testUIMigration() {
        print("\n=== Testing UI Migration ===")
        
        // Test creating nodes with the new system
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240),
            text: "A beautiful sunset over mountains"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 300, y: 0, width: 240, height: 240),
            prompt: "",
            size: CGSize(width: 1024, height: 1024)
        )
        
        // Test the new port system
        print("Text node ports:")
        for port in textNode.ports {
            print("- \(port.name): \(port.dtype.rawValue) (\(port.direction))")
        }
        
        print("Image node ports:")
        for port in imageNode.ports {
            print("- \(port.name): \(port.dtype.rawValue) (\(port.direction))")
        }
        
        // Test arg access
        let text = textNode.getArg("/text", as: String.self)
        print("Text node text: \(text ?? "nil")")
        
        let prompt = imageNode.getArg("/prompt", as: String.self)
        let width = imageNode.getArg("/size/width", as: Double.self)
        print("Image node - prompt: \(prompt ?? "nil"), width: \(width ?? 0)")
        
        // Test arg modification
        var modifiedImageNode = imageNode
        modifiedImageNode.setArg("/prompt", value: "A futuristic city")
        modifiedImageNode.setArg("/size/width", value: 2048.0)
        
        let newPrompt = modifiedImageNode.getArg("/prompt", as: String.self)
        let newWidth = modifiedImageNode.getArg("/size/width", as: Double.self)
        print("Modified image node - prompt: \(newPrompt ?? "nil"), width: \(newWidth ?? 0)")
        
        print("UI Migration test completed successfully!")
    }
    
    static func testUIBindingSystem() {
        print("\n=== Testing UI Binding System ===")
        
        // Create a simple workflow
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240),
            text: "A beautiful landscape"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 300, y: 0, width: 240, height: 240)
        )
        
        // Create graph and add nodes
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        
        // Create binding
        let textOutputPort = textNode.ports.first { $0.name == "text_output" }!
        graph.addBinding(
            sourcePortID: textOutputPort.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        print("Created binding from text output to image prompt")
        
        // Test binding resolution
        let resolvedArgs = graph.resolveArgs(for: imageNode.id)
        print("Resolved args for image node: \(resolvedArgs)")
        
        // Verify the prompt was set
        if case .object(let dict) = resolvedArgs,
           case .string(let prompt) = dict["prompt"] {
            print("✅ Binding successful! Prompt: \(prompt)")
        } else {
            print("❌ Binding failed!")
        }
        
        print("UI Binding System test completed!")
    }
    
    static func runAllTests() {
        testBasicNodeCreation()
        testJSONPointerSystem()
        testBindingSystem()
        testNodeArgHelpers()
        testUIMigration()
        testUIBindingSystem()
        print("\n=== All tests completed ===")
    }
}

// MARK: - Usage Example

extension GraphCoreTests {
    
    static func createExampleWorkflow() -> Graph {
        print("\n=== Creating Example Workflow ===")
        
        // Create nodes
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 240, height: 240),
            text: "A futuristic city at sunset"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 300, y: 0, width: 240, height: 240),
            size: CGSize(width: 1024, height: 1024)
        )
        
        // Removed ImageOutput node usage
        
        // Create graph
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        
        
        // Create bindings
        let textOutputPort = textNode.ports.first { $0.name == "text_output" }!
        
        // Text -> Image Generation
        graph.addBinding(
            sourcePortID: textOutputPort.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        
        
        print("Workflow created:")
        print("- Nodes: \(graph.nodes.count)")
        print("- Bindings: \(graph.bindings.count)")
        
        // Show resolved args for each node
        for (nodeID, node) in graph.nodes {
            let resolvedArgs = graph.resolveArgs(for: nodeID)
            print("- \(node.kind.rawValue): \(resolvedArgs)")
        }
        
        return graph
    }
}
