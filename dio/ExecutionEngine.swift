import Foundation
import Combine

// MARK: - Execution Engine

public class ExecutionEngine: ObservableObject {
    public static let shared = ExecutionEngine()
    
    private let persistence = RunPersistence.shared
    private let artifactManager = ArtifactManager.shared
    
    // Execution state
    @Published public private(set) var isExecuting = false
    @Published public private(set) var currentExecution: GraphExecution?
    @Published public private(set) var activeRuns: [UUID: Run] = [:]
    
    // Cancellation support
    private var executionTask: Task<Void, Never>?
    private var cancellationTokens: [UUID: Task<Void, Never>] = [:]
    
    private init() {}
    
    // MARK: - Main Execution Entry Point
    
    public func execute(graph: Graph) async {
        guard !isExecuting else {
            print("Execution already in progress")
            return
        }
        
        await MainActor.run {
            isExecuting = true
            currentExecution = GraphExecution(
                id: UUID(),
                graphID: graph.id,
                startedAt: Date(),
                status: .running
            )
        }
        
        executionTask = Task {
            do {
                try await performExecution(graph: graph)
            } catch {
                await handleExecutionError(error)
            }
            
            await MainActor.run {
                isExecuting = false
                if var execution = currentExecution {
                    execution.status = .completed
                    execution.finishedAt = Date()
                    currentExecution = execution
                }
            }
        }
    }
    
    // MARK: - Node-Level Execution
    
    public func executeSingleNode(_ nodeID: UUID, in graph: Graph) async {
        guard graph.nodes[nodeID] != nil else {
            print("Node not found: \(nodeID)")
            return
        }
        
        // Check if this node is already being executed
        guard activeRuns[nodeID] == nil else {
            print("Node \(nodeID) is already being executed")
            return
        }
        
        // Create a cancellation token for this node
        let nodeTask = Task {
            do {
                try await executeNode(nodeID, in: graph)
            } catch {
                await handleNodeExecutionError(error, run: activeRuns[nodeID]!)
            }
        }
        
        cancellationTokens[nodeID] = nodeTask
        
        // Wait for node execution to complete
        await nodeTask.value
        
        // Clean up
        cancellationTokens.removeValue(forKey: nodeID)
        _ = await MainActor.run {
            activeRuns.removeValue(forKey: nodeID)
        }
    }
    
    // MARK: - Node Output Helpers
    
    public func getLatestRunForNode(_ nodeID: UUID) -> Run? {
        return persistence.getRunsForNode(nodeID).first
    }
    
    public func getLatestOutputsForNode(_ nodeID: UUID) -> [Artifact] {
        guard let latestRun = getLatestRunForNode(nodeID) else { 
            // print("🔍 ExecutionEngine - No latest run found for node: \(nodeID)")
            return [] 
        }
        let artifacts = persistence.getArtifactsForRun(latestRun.id)
        // print("🔍 ExecutionEngine - Found \(artifacts.count) artifacts for run \(latestRun.id)")
        // for (index, artifact) in artifacts.enumerated() {
        //     print("🔍 ExecutionEngine - Artifact \(index): \(artifact.displayName), URI: \(artifact.uri)")
        // }
        return artifacts
    }
    
    public func getLatestPrimaryOutputForNode(_ nodeID: UUID) -> Artifact? {
        guard let latestRun = getLatestRunForNode(nodeID) else { 
            print("🔍 ExecutionEngine - No latest run found for primary output, node: \(nodeID)")
            return nil 
        }
        let primaryArtifact = persistence.getPrimaryArtifactForRun(latestRun.id)
        print("🔍 ExecutionEngine - Primary artifact for run \(latestRun.id): \(primaryArtifact?.displayName ?? "nil")")
        return primaryArtifact
    }
    
    private func findArtifactByURI(_ uri: String) -> Artifact? {
        // Find artifact by URI - this is used to link artifacts returned by adapters to runs
        return persistence.getAllArtifacts().first { $0.uri == uri }
    }
    
    public func cancelExecution() {
        executionTask?.cancel()
        
        // Cancel all active node executions
        for (nodeID, task) in cancellationTokens {
            task.cancel()
            if var run = activeRuns[nodeID] {
                run.status = .canceled
                run.finishedAt = Date()
                persistence.updateRun(run)
            }
        }
        
        cancellationTokens.removeAll()
        activeRuns.removeAll()
        
        Task { @MainActor in
            isExecuting = false
            if var execution = currentExecution {
                execution.status = .canceled
                execution.finishedAt = Date()
                currentExecution = execution
            }
        }
    }
    
    // MARK: - Core Execution Logic
    
    private func performExecution(graph: Graph) async throws {
        // 1. Validate graph
        try validateGraph(graph)
        
        // 2. Perform topological sort
        let executionOrder = try topologicalSort(graph: graph)
        
        // 3. Execute nodes in dependency order
        try await executeNodesInOrder(executionOrder, graph: graph)
    }
    
    private func validateGraph(_ graph: Graph) throws {
        // Check for empty graph
        guard !graph.nodes.isEmpty else {
            throw ExecutionError.emptyGraph
        }
        
        // Check for nodes without required inputs
        for (nodeID, node) in graph.nodes {
            let requiredInputs = node.ports.filter { $0.direction == "in" }
            let incomingBindings = graph.getBindingsForNode(nodeID)
            
            for requiredInput in requiredInputs {
                // Check if there's a binding that provides input for this port
                // The binding should target an argPath that corresponds to this input port
                let hasBinding = incomingBindings.contains { binding in
                    // Map the port name to the expected argPath
                    let expectedArgPath = getExpectedArgPath(for: node, port: requiredInput)
                    return binding.argPath == expectedArgPath
                }
                
                if !hasBinding && !hasDefaultValue(node: node, port: requiredInput) {
                    throw ExecutionError.missingRequiredInput(nodeID: nodeID, portName: requiredInput.name)
                }
            }
        }
    }
    
    private func hasDefaultValue(node: Node, port: PortDef) -> Bool {
        // Check if the port has a default value in the node's args
        let pointer = JSONPointer("/\(port.name)")
        return pointer.get(from: node.args) != nil
    }
    
    private func getExpectedArgPath(for node: Node, port: PortDef) -> String {
        // Map port names to expected arg paths based on node type
        switch node.kind {
        case .imageGeneration:
            switch port.name {
            case "prompt_input":
                return "/prompt"
            default:
                return "/\(port.name)"
            }
        default:
            return "/\(port.name)"
        }
    }
    
    // MARK: - Topological Sorting
    
    private func topologicalSort(graph: Graph) throws -> [UUID] {
        var visited = Set<UUID>()
        var visiting = Set<UUID>()
        var result: [UUID] = []
        
        func visit(_ nodeID: UUID) throws {
            if visiting.contains(nodeID) {
                throw ExecutionError.circularDependency(nodeID: nodeID)
            }
            
            if visited.contains(nodeID) {
                return
            }
            
            visiting.insert(nodeID)
            
            // Visit all dependencies first
            let dependencies = getDependencies(for: nodeID, in: graph)
            for dependency in dependencies {
                try visit(dependency)
            }
            
            visiting.remove(nodeID)
            visited.insert(nodeID)
            result.append(nodeID)
        }
        
        // Visit all nodes
        for nodeID in graph.nodes.keys {
            if !visited.contains(nodeID) {
                try visit(nodeID)
            }
        }
        
        return result
    }
    
    private func getDependencies(for nodeID: UUID, in graph: Graph) -> [UUID] {
        let bindings = graph.getBindingsForNode(nodeID)
        var dependencies: [UUID] = []
        
        for binding in bindings {
            // Find the source node for this binding
            if let sourceNode = findNodeWithPort(binding.sourcePortID, in: graph) {
                dependencies.append(sourceNode.id)
            }
        }
        
        return dependencies
    }
    
    private func findNodeWithPort(_ portID: UUID, in graph: Graph) -> Node? {
        return graph.nodes.values.first { node in
            node.ports.contains { $0.id == portID }
        }
    }
    
    // MARK: - Node Execution
    
    private func executeNodesInOrder(_ nodeOrder: [UUID], graph: Graph) async throws {
        // Group nodes by execution level (nodes that can run in parallel)
        let executionLevels = groupNodesByExecutionLevel(nodeOrder, graph: graph)
        
        for level in executionLevels {
            // Execute all nodes in this level in parallel
            try await withThrowingTaskGroup(of: Void.self) { group in
                for nodeID in level {
                    group.addTask {
                        try await self.executeNode(nodeID, in: graph)
                    }
                }
                
                // Wait for all nodes in this level to complete
                try await group.waitForAll()
            }
        }
    }
    
    private func groupNodesByExecutionLevel(_ nodeOrder: [UUID], graph: Graph) -> [[UUID]] {
        var levels: [[UUID]] = []
        var processed = Set<UUID>()
        
        for nodeID in nodeOrder {
            if processed.contains(nodeID) {
                continue
            }
            
            // Find all nodes that can run in parallel with this one
            let currentLevel = findParallelNodes(startingWith: nodeID, in: graph, processed: processed)
            levels.append(currentLevel)
            processed.formUnion(currentLevel)
        }
        
        return levels
    }
    
    private func findParallelNodes(startingWith nodeID: UUID, in graph: Graph, processed: Set<UUID>) -> [UUID] {
        var parallelNodes: [UUID] = [nodeID]
        var toCheck = [nodeID]
        
        while !toCheck.isEmpty {
            let currentNodeID = toCheck.removeFirst()
            let dependencies = getDependencies(for: currentNodeID, in: graph)
            
            // Find nodes that have the same dependencies and can run in parallel
            for (otherNodeID, _) in graph.nodes {
                if otherNodeID == currentNodeID || processed.contains(otherNodeID) || parallelNodes.contains(otherNodeID) {
                    continue
                }
                
                let otherDependencies = getDependencies(for: otherNodeID, in: graph)
                
                // Check if this node can run in parallel (no dependency relationship)
                if !dependencies.contains(otherNodeID) && !otherDependencies.contains(currentNodeID) {
                    // Check if all dependencies of the other node are already processed
                    let allDependenciesProcessed = otherDependencies.allSatisfy { processed.contains($0) }
                    if allDependenciesProcessed {
                        parallelNodes.append(otherNodeID)
                        toCheck.append(otherNodeID)
                    }
                }
            }
        }
        
        return parallelNodes
    }
    
    private func executeNode(_ nodeID: UUID, in graph: Graph) async throws {
        guard let node = graph.nodes[nodeID] else {
            throw ExecutionError.nodeNotFound(nodeID: nodeID)
        }
        
        // Handle input nodes differently - they don't need execution
        if node.kind.isInputNode {
            try await handleInputNode(nodeID, in: graph)
            return
        }
        
        // Handle execution nodes (generation, processing, etc.)
        try await handleExecutionNode(nodeID, in: graph)
    }
    
    // MARK: - Input Node Handling
    
    private func handleInputNode(_ nodeID: UUID, in graph: Graph) async throws {
        guard graph.nodes[nodeID] != nil else {
            throw ExecutionError.nodeNotFound(nodeID: nodeID)
        }
        
        // Input nodes don't create runs or go through adapters
        // They just pass their input values directly to their outputs
        // This is handled by the graph resolution system
        
        // For now, we just mark the node as "completed" without creating a run
        // The actual value passing is handled by getOutputValue() in the graph resolution
        print("Input node \(nodeID) processed (no execution needed)")
    }
    
    // MARK: - Execution Node Handling
    
    private func handleExecutionNode(_ nodeID: UUID, in graph: Graph) async throws {
        guard let node = graph.nodes[nodeID] else {
            throw ExecutionError.nodeNotFound(nodeID: nodeID)
        }
        
        // Create run record for execution nodes
        let modelRef: ModelRef
        if node.kind == .imageGeneration {
            // Minimal default FAL model for image generation
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/flux/schnell",
                endpoint: "/image/generate",
                mode: "sync"
            )
        } else if node.kind == .imageEdit {
            // FAL model for image editing using nano-banana
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/nano-banana/edit",
                endpoint: "/fal-ai/nano-banana/edit",
                mode: "async"
            )
        } else if node.kind == .seedreamEdit {
            // FAL SeedDream v4 Edit (image-to-image)
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/bytedance/seedream/v4/edit",
                endpoint: "/fal-ai/bytedance/seedream/v4/edit",
                mode: "async"
            )
        } else if node.kind == .videoGeneration {
            // OpenAI Sora default
            let chosenModel = node.getArg("/model", as: String.self) ?? "sora-2"
            modelRef = ModelRef(
                provider: "OpenAI",
                modelID: chosenModel,
                endpoint: "/videos",
                mode: "async"
            )
        } else if node.kind == .imageToVideo {
            // FAL Kling image-to-video
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/kling-video/v2.5-turbo/pro/image-to-video",
                endpoint: "/fal-ai/kling-video/v2.5-turbo/pro/image-to-video",
                mode: "async"
            )
        } else if node.kind == .seedanceImageToVideo {
            // FAL Seedance Pro image-to-video
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/bytedance/seedance/v1/pro/image-to-video",
                endpoint: "/fal-ai/bytedance/seedance/v1/pro/image-to-video",
                mode: "async"
            )
        } else if node.kind == .wanAnimateMove {
            // FAL WAN animate/move
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/wan/v2.2-14b/animate/move",
                endpoint: "/fal-ai/wan/v2.2-14b/animate/move",
                mode: "async"
            )
        } else if node.kind == .wanAnimateReplace {
            // FAL WAN animate/replace
            modelRef = ModelRef(
                provider: "FAL",
                modelID: "fal-ai/wan/v2.2-14b/animate/replace",
                endpoint: "/fal-ai/wan/v2.2-14b/animate/replace",
                mode: "async"
            )
        } else {
            modelRef = ModelRef(
                provider: "Mock",
                modelID: node.kind.rawValue,
                endpoint: "/execute"
            )
        }
        
        let resolvedArgs = graph.resolveArgs(for: nodeID)
        let resolvedInputs = getResolvedInputs(for: nodeID, in: graph)
        
    let run = persistence.createRun(
            nodeID: nodeID,
            model: modelRef,
            inputParams: resolvedArgs,
            resolvedInputs: resolvedInputs,
            nodeSchemaVersion: node.schemaVersion,
            nodeArgsSnapshot: node.args
        )
        
        await MainActor.run {
            activeRuns[nodeID] = run
        }
        
        // Create cancellation token for this node
        let nodeTask = Task {
            do {
                try await performNodeExecution(run: run, node: node, graph: graph)
            } catch {
                await handleNodeExecutionError(error, run: run)
            }
        }
        
        cancellationTokens[nodeID] = nodeTask
        
        // Wait for node execution to complete
        await nodeTask.value
        
        // Clean up
        cancellationTokens.removeValue(forKey: nodeID)
        _ = await MainActor.run {
            activeRuns.removeValue(forKey: nodeID)
        }
    }
    
    private func getResolvedInputs(for nodeID: UUID, in graph: Graph) -> JSONValue {
        let bindings = graph.getBindingsForNode(nodeID)
        var resolvedInputs: [String: JSONValue] = [:]
        
        for binding in bindings {
            if let sourceNode = findNodeWithPort(binding.sourcePortID, in: graph),
               let sourcePort = sourceNode.ports.first(where: { $0.id == binding.sourcePortID }) {
                
                let outputValue = getOutputValue(from: sourceNode, port: sourcePort)
                resolvedInputs[sourcePort.name] = outputValue
            }
        }
        
        return .object(resolvedInputs)
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
        // Get the latest run for this node
        let latestRun = getLatestRunForNode(node.id)
        
        if let run = latestRun, run.status == .succeeded {
            // Get the primary artifact for this run
            let primaryArtifact = getLatestPrimaryOutputForNode(node.id)
            
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
    
    // MARK: - Node Execution Implementation
    
    private func performNodeExecution(run: Run, node: Node, graph: Graph) async throws {
        // Update run status to running
        var updatedRun = run
        updatedRun.status = .running
        persistence.updateRun(updatedRun)
        
        // Get the appropriate adapter for this node
        let adapter = getAdapterForNode(node)
        
        // Create invocation request
        var params = run.inputParams
        // Attach resolved inputs under /resolved for adapters that need them
        let resolved = run.resolvedInputs
        if case var .object(obj) = params {
            obj["resolved"] = resolved
            params = .object(obj)
        }
        let request = InvocationRequest(
            model: run.model,
            params: params,
            files: nil,
            runKey: run.runKey,
            credentialID: UUID(), // Mock credential
            timeout: 30.0
        )
        
        // Invoke the adapter
        print("[ExecutionEngine] Invoking adapter=\(adapter.provider) nodeKind=\(node.kind) model=\(request.model.modelID) endpoint=\(request.model.endpoint) runKey=\(request.runKey)")
        print("[ExecutionEngine] Params: \(run.inputParams.displayString)")
        let response = try await adapter.invoke(request)
        let initialProgress = extractProgress(from: response)
        if let p = initialProgress {
            print(String(format: "[ExecutionEngine] Initial response status=%@ progress=%.1f%% error=%@: %@", response.status, p, response.errorCode ?? "none", response.errorMessage ?? ""))
        } else {
            print("[ExecutionEngine] Initial response status=\(response.status) error=\(response.errorCode ?? "none"): \(response.errorMessage ?? "")")
        }
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Handle the response
        if response.status == "succeeded" {
            updatedRun = try await handleSuccessfulResponse(response, run: updatedRun, node: node)
            print("[ExecutionEngine] Run succeeded runId=\(updatedRun.id) artifacts=\(updatedRun.outputsMeta?.displayString ?? "nil")")
        } else if response.status == "failed" {
            updatedRun = handleFailedResponse(response, run: updatedRun)
            print("[ExecutionEngine] Run failed runId=\(updatedRun.id) code=\(updatedRun.errorCode ?? "nil") message=\(updatedRun.errorMessage ?? "nil")")
            print("[ExecutionEngine] Note: initial invoke failed (no poll). provider=\(adapter.provider) model=\(run.model.modelID) jobID=\(response.jobID ?? "nil")")
        } else if response.status == "queued" || response.status == "running" {
            // Handle async responses
            print("[ExecutionEngine] Async flow started jobId=\(response.jobID ?? "nil")")
            // Persist jobID for later polling/retry
            updatedRun.jobID = response.jobID
            persistence.updateRun(updatedRun)
            print("[ExecutionEngine] Saved jobID=\(updatedRun.jobID ?? "nil") for node=\(node.id). Entering poll loop…")
            updatedRun = try await handleAsyncResponse(response, run: updatedRun, adapter: adapter, node: node)
            print("[ExecutionEngine] Async flow finished status=\(updatedRun.status.rawValue)")
        }
        
        persistence.updateRun(updatedRun)
    }
    
    private func getAdapterForNode(_ node: Node) -> CloudAdapter {
        if node.kind == .imageGeneration || node.kind == .imageEdit || node.kind == .seedreamEdit || node.kind == .imageToVideo || node.kind == .wanAnimateMove || node.kind == .wanAnimateReplace {
            return AdapterRegistry.shared.getAdapter(for: "FAL") ?? FALAdapter()
        } else if node.kind == .videoGeneration {
            return AdapterRegistry.shared.getAdapter(for: "OpenAI") ?? OpenAIAdapter()
        }
        return AdapterRegistry.shared.getAdapter(for: "Mock") ?? MockAdapter()
    }
    
    private func handleSuccessfulResponse(_ response: InvocationResponse, run: Run, node: Node) async throws -> Run {
        // Adapters are responsible for creating and storing their own artifacts
        // The ExecutionEngine links artifacts to runs when they're returned in the response
        
        // Link any artifacts returned by the adapter to this run
        var updatedRun = run
        if let artifactRefs = response.artifacts, !artifactRefs.isEmpty {
            for (index, artifactRef) in artifactRefs.enumerated() {
                // Find the artifact by URI (since adapters store artifacts with their URIs)
                if let artifact = findArtifactByURI(artifactRef.uri) {
                    let role = index == 0 ? "primary" : "preview"
                    persistence.linkRunToArtifact(runID: updatedRun.id, artifactID: artifact.id, role: role, index: index)
                }
            }
        }
        
        // Update run with results
        updatedRun.status = .succeeded
        updatedRun.finishedAt = Date()
        updatedRun.billedUSD = response.billedUSD
        updatedRun.outputsMeta = response.outputs
        updatedRun.adapterDebug = response.vendorMeta
        return updatedRun
    }
    
    private func handleFailedResponse(_ response: InvocationResponse, run: Run) -> Run {
        var updatedRun = run
        updatedRun.status = .failed
        updatedRun.finishedAt = Date()
        updatedRun.errorCode = response.errorCode
        updatedRun.errorMessage = response.errorMessage
        updatedRun.billedUSD = response.billedUSD
        print("[ExecutionEngine] handleFailedResponse code=\(updatedRun.errorCode ?? "nil") message=\(updatedRun.errorMessage ?? "nil") billed=\(String(describing: updatedRun.billedUSD))")
        return updatedRun
    }
    
    private func handleAsyncResponse(_ response: InvocationResponse, run: Run, adapter: CloudAdapter, node: Node) async throws -> Run {
        guard let jobID = response.jobID else {
            throw ExecutionError.executionCancelled
        }
        
        // Poll for completion
        var pollCount = 0
        let maxPolls = 600 // 10 minutes max (1s per poll)
        var localRun = run
        
        while pollCount < maxPolls {
            try Task.checkCancellation()
            print("[ExecutionEngine] Polling jobId=\(jobID) attempt=\(pollCount+1)/\(maxPolls)")
            // Attempt poll; treat thrown errors as transient and allow manual retry
            let pollResponse: InvocationResponse
            do {
                pollResponse = try await adapter.poll(jobID: jobID, credentialID: UUID())
                // Clear any transient poll flags if previously set
                localRun.pendingManualPoll = false
                localRun.lastPollErrorCode = nil
                localRun.lastPollErrorMessage = nil
            } catch {
                print("[ExecutionEngine] Poll error: \(error.localizedDescription)")
                localRun.pendingManualPoll = true
                localRun.lastPollErrorCode = (error as NSError).domain
                localRun.lastPollErrorMessage = error.localizedDescription
                persistence.updateRun(localRun)
                await MainActor.run {
                    let runSnapshot = localRun
                    self.activeRuns[node.id] = runSnapshot
                }
                return localRun
            }
            let progress = extractProgress(from: pollResponse)
            if let p = progress {
                print(String(format: "[ExecutionEngine] Poll response status=%@ progress=%.1f%%", pollResponse.status, p))
            } else {
                print("[ExecutionEngine] Poll response status=\(pollResponse.status)")
            }
            
            // Update in-flight run with latest status and progress for UI
            if pollResponse.status == "queued" {
                localRun.status = .queued
            } else if pollResponse.status == "running" {
                localRun.status = .running
            }
            localRun.outputsMeta = pollResponse.outputs ?? localRun.outputsMeta
            localRun.adapterDebug = pollResponse.vendorMeta ?? localRun.adapterDebug
            persistence.updateRun(localRun)
            await MainActor.run {
                let runSnapshot = localRun
                self.activeRuns[node.id] = runSnapshot
            }
            
            if pollResponse.status == "succeeded" {
                localRun = try await handleSuccessfulResponse(pollResponse, run: localRun, node: node)
                return localRun
            } else if pollResponse.status == "failed" {
                let lastProgress = extractProgress(from: pollResponse)
                if let p = lastProgress {
                    print(String(format: "[ExecutionEngine] Final progress before failure: %.1f%%", p))
                }
                if let meta = pollResponse.vendorMeta {
                    print("[ExecutionEngine] Vendor meta on failure: \(meta.displayString)")
                }
                localRun = handleFailedResponse(pollResponse, run: localRun)
                return localRun
            } else if pollResponse.status == "cancelled" {
                localRun.status = .canceled
                localRun.finishedAt = Date()
                print("[ExecutionEngine] Job cancelled jobId=\(jobID)")
                return localRun
            }
            
            // Wait before next poll
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds
            pollCount += 1
        }
        
        // Timeout
        localRun.status = .failed
        localRun.finishedAt = Date()
        localRun.errorCode = "TIMEOUT"
        localRun.errorMessage = "Async operation timed out"
        print("[ExecutionEngine] Async timeout jobId=\(jobID)")
        return localRun
    }

    // MARK: - Manual Poll Retry API
    public func retryPolling(node: Node) async {
        print("[ExecutionEngine] retryPolling requested for node=\(node.id)")
        guard var latestRun = persistence.getRunsForNode(node.id).first else {
            print("[ExecutionEngine] retryPolling: no runs found for node")
            return
        }
        guard latestRun.status == .queued || latestRun.status == .running else {
            print("[ExecutionEngine] retryPolling: run not in queued/running state; status=\(latestRun.status.rawValue)")
            return
        }
        guard let jobID = latestRun.jobID else {
            print("[ExecutionEngine] retryPolling: missing jobID; cannot poll")
            return
        }
        let adapter = getAdapterForNode(node)
        do {
            let pollResponse = try await adapter.poll(jobID: jobID, credentialID: UUID())
            print("[ExecutionEngine] retryPolling: received status=\(pollResponse.status)")
            if pollResponse.status == "succeeded" {
                let updated = try await handleSuccessfulResponse(pollResponse, run: latestRun, node: node)
                persistence.updateRun(updated)
                await MainActor.run { self.activeRuns[node.id] = updated }
                print("[ExecutionEngine] retryPolling: run succeeded runId=\(updated.id)")
            } else if pollResponse.status == "failed" {
                let failed = handleFailedResponse(pollResponse, run: latestRun)
                persistence.updateRun(failed)
                await MainActor.run { self.activeRuns[node.id] = failed }
                print("[ExecutionEngine] retryPolling: run failed runId=\(failed.id) code=\(failed.errorCode ?? "nil") message=\(failed.errorMessage ?? "nil")")
            } else {
                latestRun.status = (pollResponse.status == "running") ? .running : .queued
                latestRun.outputsMeta = pollResponse.outputs ?? latestRun.outputsMeta
                latestRun.adapterDebug = pollResponse.vendorMeta ?? latestRun.adapterDebug
                latestRun.pendingManualPoll = false
                latestRun.lastPollErrorCode = nil
                latestRun.lastPollErrorMessage = nil
                persistence.updateRun(latestRun)
                await MainActor.run { self.activeRuns[node.id] = latestRun }
                print("[ExecutionEngine] retryPolling: updated in-flight run status=\(latestRun.status.rawValue)")
            }
        } catch {
            print("[ExecutionEngine] retryPolling: poll error=\(error.localizedDescription)")
            latestRun.pendingManualPoll = true
            latestRun.lastPollErrorCode = (error as NSError).domain
            latestRun.lastPollErrorMessage = error.localizedDescription
            persistence.updateRun(latestRun)
            await MainActor.run { self.activeRuns[node.id] = latestRun }
            print("[ExecutionEngine] retryPolling: re-marked pendingManualPoll for runId=\(latestRun.id)")
        }
    }

    // MARK: - Progress Extraction
    private func extractProgress(from response: InvocationResponse) -> Double? {
        let pointer = JSONPointer("/progress")
        if let outputs = response.outputs, let value = pointer.get(from: outputs) {
            switch value {
            case .number(let n): return n
            case .string(let s): return Double(s)
            default: break
            }
        }
        if let meta = response.vendorMeta, let value = pointer.get(from: meta) {
            switch value {
            case .number(let n): return n
            case .string(let s): return Double(s)
            default: break
            }
        }
        return nil
    }
    
    
    // MARK: - Error Handling
    
    private func handleNodeExecutionError(_ error: Error, run: Run) async {
        var updatedRun = run
        updatedRun.status = .failed
        updatedRun.finishedAt = Date()
        updatedRun.errorMessage = error.localizedDescription
        
        if let executionError = error as? ExecutionError {
            updatedRun.errorCode = executionError.errorCode
        }
        
        print("[ExecutionEngine] Node execution error runId=\(run.id) code=\(updatedRun.errorCode ?? "nil"): \(updatedRun.errorMessage ?? "nil")")
        persistence.updateRun(updatedRun)
    }
    
    private func handleExecutionError(_ error: Error) async {
        await MainActor.run {
            if var execution = currentExecution {
                execution.status = .failed
                execution.finishedAt = Date()
                execution.errorMessage = error.localizedDescription
                currentExecution = execution
                print("[ExecutionEngine] Execution error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Supporting Types

public struct GraphExecution: Codable, Identifiable {
    public let id: UUID
    public let graphID: UUID
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: ExecutionStatus
    public var errorMessage: String?
    
    public init(id: UUID = UUID(), graphID: UUID, startedAt: Date, status: ExecutionStatus = .running) {
        self.id = id
        self.graphID = graphID
        self.startedAt = startedAt
        self.status = status
    }
    
    public var duration: TimeInterval? {
        guard let finishedAt = finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

public enum ExecutionStatus: String, Codable {
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case canceled = "canceled"
}


// MARK: - Execution Errors

public enum ExecutionError: Error, LocalizedError {
    case emptyGraph
    case circularDependency(nodeID: UUID)
    case missingRequiredInput(nodeID: UUID, portName: String)
    case nodeNotFound(nodeID: UUID)
    case executionCancelled
    
    public var errorDescription: String? {
        switch self {
        case .emptyGraph:
            return "Cannot execute empty graph"
        case .circularDependency(let nodeID):
            return "Circular dependency detected involving node \(nodeID)"
        case .missingRequiredInput(let nodeID, let portName):
            return "Node \(nodeID) is missing required input: \(portName)"
        case .nodeNotFound(let nodeID):
            return "Node not found: \(nodeID)"
        case .executionCancelled:
            return "Execution was cancelled"
        }
    }
    
    public var errorCode: String {
        switch self {
        case .emptyGraph: return "EMPTY_GRAPH"
        case .circularDependency: return "CIRCULAR_DEPENDENCY"
        case .missingRequiredInput: return "MISSING_INPUT"
        case .nodeNotFound: return "NODE_NOT_FOUND"
        case .executionCancelled: return "CANCELLED"
        }
    }
}
