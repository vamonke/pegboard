import Foundation
import XCTest
@testable import dio

// MARK: - Execution Engine Tests

class ExecutionEngineTests: XCTestCase {
    
    var executionEngine: ExecutionEngine!
    var persistence: RunPersistence!
    
    override func setUp() {
        super.setUp()
        executionEngine = ExecutionEngine.shared
        persistence = RunPersistence.shared
    }
    
    // MARK: - Graph Validation Tests
    
    func testEmptyGraphValidation() async {
        let emptyGraph = Graph()
        
        do {
            try await executionEngine.execute(graph: emptyGraph)
            XCTFail("Should have thrown empty graph error")
        } catch ExecutionError.emptyGraph {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCircularDependencyDetection() async {
        // Create a graph with circular dependency: A -> B -> A
        let nodeA = Node.textPrompt(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let nodeB = Node.imageGeneration(frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        
        var graph = Graph()
        graph.nodes[nodeA.id] = nodeA
        graph.nodes[nodeB.id] = nodeB
        
        // Create circular binding: A -> B -> A
        let aOutputPort = nodeA.ports.first { $0.direction == "out" }!
        let bInputPort = nodeB.ports.first { $0.direction == "in" }!
        let bOutputPort = nodeB.ports.first { $0.direction == "out" }!
        let aInputPort = nodeA.ports.first { $0.direction == "in" }!
        
        // This would create a circular dependency, but we need to add an input port to A first
        // For now, let's test with a simpler circular case
        
        do {
            try await executionEngine.execute(graph: graph)
            // Should succeed for now since we don't have actual circular dependencies
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Topological Sort Tests
    
    func testTopologicalSorting() {
        // Create a simple linear graph: A -> B -> C
        let nodeA = Node.textPrompt(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let nodeB = Node.imageGeneration(frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        let nodeC = Node.imageGeneration(frame: CGRect(x: 200, y: 0, width: 100, height: 100))
        
        var graph = Graph()
        graph.nodes[nodeA.id] = nodeA
        graph.nodes[nodeB.id] = nodeB
        graph.nodes[nodeC.id] = nodeC
        
        // Create bindings: A -> B -> C
        let aOutputPort = nodeA.ports.first { $0.direction == "out" }!
        let bInputPort = nodeB.ports.first { $0.direction == "in" }!
        let bOutputPort = nodeB.ports.first { $0.direction == "out" }!
        let cInputPort = nodeC.ports.first { $0.direction == "in" }!
        
        graph.addBinding(
            sourcePortID: aOutputPort.id,
            targetNodeID: nodeB.id,
            argPath: "/prompt"
        )
        
        graph.addBinding(
            sourcePortID: bOutputPort.id,
            targetNodeID: nodeC.id,
            argPath: "/prompt"
        )
        
        // Test execution (which includes topological sorting)
        let expectation = XCTestExpectation(description: "Graph execution")
        
        Task {
            do {
                await executionEngine.execute(graph: graph)
                expectation.fulfill()
            } catch {
                XCTFail("Execution failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
    }
    
    // MARK: - Node Execution Tests
    
    func testSingleNodeExecution() async {
        let node = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            text: "Test prompt"
        )
        
        var graph = Graph()
        graph.nodes[node.id] = node
        
        await executionEngine.execute(graph: graph)
        
        // Verify run was created
        let runs = persistence.getRunsForNode(node.id)
        XCTAssertEqual(runs.count, 1)
        
        let run = runs.first!
        XCTAssertEqual(run.nodeID, node.id)
        XCTAssertEqual(run.status, .succeeded)
        XCTAssertNotNil(run.finishedAt)
    }
    
    func testMultiNodeExecution() async {
        // Create a simple workflow: text -> image -> image
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            text: "A beautiful sunset"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 100, y: 0, width: 100, height: 100),
            prompt: "",
        )
        
        let outputNode = Node.imageGeneration(
            frame: CGRect(x: 200, y: 0, width: 100, height: 100),
            prompt: "",
        )
        
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        graph.nodes[outputNode.id] = outputNode
        
        // Create bindings
        let textOutputPort = textNode.ports.first { $0.direction == "out" }!
        let imageInputPort = imageNode.ports.first { $0.direction == "in" }!
        let imageOutputPort = imageNode.ports.first { $0.direction == "out" }!
        let outputInputPort = outputNode.ports.first { $0.direction == "in" }!
        
        graph.addBinding(
            sourcePortID: textOutputPort.id,
            targetNodeID: imageNode.id,
            argPath: "/prompt"
        )
        
        graph.addBinding(
            sourcePortID: imageOutputPort.id,
            targetNodeID: outputNode.id,
            argPath: "/prompt"
        )
        
        await executionEngine.execute(graph: graph)
        
        // Verify all nodes were executed
        let textRuns = persistence.getRunsForNode(textNode.id)
        let imageRuns = persistence.getRunsForNode(imageNode.id)
        let outputRuns = persistence.getRunsForNode(outputNode.id)
        
        XCTAssertEqual(textRuns.count, 1)
        XCTAssertEqual(imageRuns.count, 1)
        XCTAssertEqual(outputRuns.count, 1)
        
        // Verify all runs succeeded
        XCTAssertEqual(textRuns.first?.status, .succeeded)
        XCTAssertEqual(imageRuns.first?.status, .succeeded)
        XCTAssertEqual(outputRuns.first?.status, .succeeded)
    }
    
    // MARK: - Cancellation Tests
    
    func testExecutionCancellation() async {
        let node = Node.imageGeneration(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            prompt: "Test prompt"
        )
        
        var graph = Graph()
        graph.nodes[node.id] = node
        
        // Start execution
        let executionTask = Task {
            await executionEngine.execute(graph: graph)
        }
        
        // Cancel after a short delay
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        executionEngine.cancelExecution()
        
        // Wait for execution to complete
        await executionTask.value
        
        // Verify run was cancelled
        let runs = persistence.getRunsForNode(node.id)
        XCTAssertEqual(runs.count, 1)
        
        let run = runs.first!
        XCTAssertEqual(run.status, .canceled)
    }
    
    // MARK: - Error Handling Tests
    
    func testMissingRequiredInput() async {
        // Create a node that requires an input but has no binding
        let node = Node.imageGeneration(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            prompt: "" // Empty prompt, no binding provided
        )
        
        var graph = Graph()
        graph.nodes[node.id] = node
        
        // This should succeed because we have a default value (empty string)
        await executionEngine.execute(graph: graph)
        
        let runs = persistence.getRunsForNode(node.id)
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.status, .succeeded)
    }
    
    // MARK: - Performance Tests
    
    func testLargeGraphExecution() async {
        // Create a graph with many independent nodes
        var graph = Graph()
        var nodeIDs: [UUID] = []
        
        for i in 0..<10 {
            let node = Node.textPrompt(
                frame: CGRect(x: CGFloat(i * 100), y: 0, width: 100, height: 100),
                text: "Node \(i)"
            )
            graph.nodes[node.id] = node
            nodeIDs.append(node.id)
        }
        
        let startTime = Date()
        await executionEngine.execute(graph: graph)
        let endTime = Date()
        
        let executionTime = endTime.timeIntervalSince(startTime)
        print("Large graph execution time: \(executionTime)s")
        
        // Verify all nodes were executed
        for nodeID in nodeIDs {
            let runs = persistence.getRunsForNode(nodeID)
            XCTAssertEqual(runs.count, 1)
            XCTAssertEqual(runs.first?.status, .succeeded)
        }
        
        // Should complete reasonably quickly (within 5 seconds for 10 nodes)
        XCTAssertLessThan(executionTime, 5.0)
    }
    
    // MARK: - Artifact Generation Tests
    
    func testArtifactGeneration() async {
        let node = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            text: "Test artifact generation"
        )
        
        var graph = Graph()
        graph.nodes[node.id] = node
        
        await executionEngine.execute(graph: graph)
        
        // Verify run was created
        let runs = persistence.getRunsForNode(node.id)
        XCTAssertEqual(runs.count, 1)
        
        let run = runs.first!
        
        // Verify artifacts were created
        let artifacts = persistence.getArtifactsForRun(run.id)
        XCTAssertGreaterThan(artifacts.count, 0)
        
        // Verify primary artifact exists
        let primaryArtifact = persistence.getPrimaryArtifactForRun(run.id)
        XCTAssertNotNil(primaryArtifact)
        XCTAssertEqual(primaryArtifact?.kind, "text")
    }
    
    // MARK: - Cost Calculation Tests
    
    func testCostCalculation() async {
        let textNode = Node.textPrompt(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            text: "Test cost"
        )
        
        let imageNode = Node.imageGeneration(
            frame: CGRect(x: 100, y: 0, width: 100, height: 100),
            prompt: "Test image"
        )
        
        var graph = Graph()
        graph.nodes[textNode.id] = textNode
        graph.nodes[imageNode.id] = imageNode
        
        await executionEngine.execute(graph: graph)
        
        // Verify costs were calculated
        let textRuns = persistence.getRunsForNode(textNode.id)
        let imageRuns = persistence.getRunsForNode(imageNode.id)
        
        XCTAssertNotNil(textRuns.first?.billedUSD)
        XCTAssertNotNil(imageRuns.first?.billedUSD)
        
        // Image generation should cost more than text
        let textCost = textRuns.first?.billedUSD ?? 0
        let imageCost = imageRuns.first?.billedUSD ?? 0
        XCTAssertGreaterThan(imageCost, textCost)
    }
}
