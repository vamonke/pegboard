# Phase 2: Execution Engine Foundation

## Overview
Build the execution engine that transforms your clean graph architecture into a working system that can actually run nodes and track their execution state.

## Current State (Post-Phase 1)
✅ **Clean Architecture**: V1 legacy code removed, modern `Node`/`Graph`/`Binding` system in place  
✅ **Data Model**: JSON-based args, type-safe ports, JSON Pointer bindings  
✅ **UI Foundation**: Node creation, editing, visual connections working  
✅ **Binding System**: Data flow resolution between nodes implemented  

## Phase 2 Goals
1. **Run & Artifact System**: Track every execution with immutable records
2. **Execution Engine**: Topological execution with proper dependency resolution
3. **Mock Adapter**: Simulate real API calls for testing
4. **Run History UI**: Show execution status, costs, and results
5. **Error Handling**: Proper error states and user feedback

---

## 2.1 Run & Artifact Models (Week 1)

### Core Data Structures
```swift
// Execution tracking
struct Run: Codable, Identifiable {
    let id: UUID
    let nodeID: UUID
    let runKey: String          // ULID for idempotency
    let startedAt: Date
    var finishedAt: Date?
    var status: RunStatus       // queued|running|succeeded|failed|canceled
    let model: ModelRef         // provider:model_id:endpoint
    let inputParams: JSONValue  // resolved args after bindings
    let resolvedInputs: JSONValue // values from upstream ports
    var outputsMeta: JSONValue? // lightweight descriptors
    var errorCode: String?
    var errorMessage: String?
    var billedUSD: Decimal?
    let nodeSchemaVersion: Int
    let nodeArgsSnapshot: JSONValue
    var adapterDebug: JSONValue?
}

// Output artifacts (images, videos, text files)
struct Artifact: Codable, Identifiable {
    let id: UUID
    let kind: String            // "image"|"video"|"json"|"text"
    let mimeType: String
    let storage: String         // "local"|"remote"
    let uri: String            // file://, ph://, https://
    let contentHash: String    // SHA-256
    let sizePx: CGSize?
    let durationSec: Float?
    let createdAt: Date
}

// Link runs to their outputs
struct RunArtifact: Codable {
    let runID: UUID
    let artifactID: UUID
    let role: String           // "primary"|"preview"|"thumb"|"log"
    let index: Int             // for multi-image/video sets
}

// Model references for cloud providers
struct ModelRef: Codable {
    let provider: String       // "FAL", "WaveSpeed", "Mock"
    let modelID: String        // "sdxl-turbo", "flux-pro-1.1"
    let endpoint: String       // "/image/generate"
    let mode: String          // "sync"|"async"
    let defaultArgs: JSONValue
}
```

### Tasks
- [x] Create `Run`, `Artifact`, `RunArtifact`, `ModelRef` models
- [x] Add run status enum and helper methods
- [x] Create artifact storage system (local file management)
- [x] Add content hashing for deduplication
- [x] Create run persistence layer (Core Data or SQLite)

---

## 2.2 Execution Engine Core (Week 2)

### Topological Execution
```swift
class ExecutionEngine {
    func execute(graph: Graph) async {
        // 1. Topological sort nodes by dependencies
        // 2. Execute ready nodes in parallel where possible
        // 3. Handle async operations with proper cancellation
        // 4. Update run status and propagate results
    }
    
    private func resolveDependencies(for nodeID: UUID, in graph: Graph) -> [UUID] {
        // Find all nodes that this node depends on
    }
    
    private func executeNode(_ node: Node, with resolvedArgs: JSONValue) async -> Run {
        // Create run record, invoke adapter, handle results
    }
}
```

### Dependency Resolution
- [x] Implement topological sorting algorithm
- [x] Handle circular dependency detection
- [x] Support parallel execution of independent nodes
- [x] Implement proper cancellation propagation

### Run Lifecycle Management
- [x] Create run records before execution
- [x] Update status throughout execution
- [x] Handle success/failure states
- [x] Implement retry logic for transient failures

---

## 2.3 Mock Adapter System (Week 3)

### Adapter Protocol
```swift
protocol CloudAdapter {
    var provider: String { get }
    func invoke(_ request: InvocationRequest) async throws -> InvocationResponse
    func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse
}

struct InvocationRequest: Codable {
    let model: ModelRef
    let params: JSONValue
    let files: [URL]?
    let runKey: String
    let credentialID: UUID
}

struct InvocationResponse: Codable {
    let status: String
    let outputs: JSONValue?
    let artifacts: [ArtifactRef]?
    let errorCode: String?
    let errorMessage: String?
    let billedUSD: Decimal?
    let vendorMeta: JSONValue?
}
```

### Mock Implementation
- [x] Create `MockAdapter` that simulates API calls
- [x] Generate realistic delays and responses
- [x] Support different node types (text, image, video)
- [x] Implement proper error simulation
- [x] Add cost simulation for testing

### Node-Specific Mock Logic
- [x] **TextPrompt**: Return input text as-is
- [x] **ImageGeneration**: Generate placeholder images with prompt text
- [x] **ImageOutput**: Save images to local storage
- [x] **OpenaiSora**: Create placeholder video files

---

## 2.4 Run History UI (Week 4)

### Run List View
```swift
struct RunHistoryView: View {
    let node: Node
    @State private var runs: [Run] = []
    
    var body: some View {
        List(runs) { run in
            RunRowView(run: run)
        }
        .onAppear { loadRuns() }
    }
}
```

### Run Status Indicators
- [x] Visual status indicators (queued, running, succeeded, failed)
- [x] Progress bars for long-running operations
- [x] Cost display for each run
- [x] Error messages with actionable feedback
- [x] "Rerun with changes" functionality

### Artifact Display
- [x] Thumbnail generation for images/videos
- [x] Preview modals for artifacts
- [x] Download/save functionality
- [x] Artifact metadata display

---

## 2.5 Integration & Testing (Week 5)

### Graph Integration
- [x] Add execution triggers to ContentView
- [x] Implement "Run Graph" button
- [x] Add execution status indicators to nodes
- [x] Show run history in node context menus

### Error Handling
- [x] Network error handling with retry logic
- [x] Validation error display
- [x] Graceful degradation for failed nodes
- [x] User-friendly error messages

### Performance & UX
- [x] Debounced execution (300-600ms)
- [x] Background execution support
- [x] Progress indicators during execution
- [x] Cancellation support

---

## Success Criteria

### Functional Requirements
- [x] Can execute a simple text → image workflow
- [x] Tracks all runs with proper status updates
- [x] Generates and stores artifacts correctly
- [x] Shows execution history in UI
- [x] Handles errors gracefully

### Technical Requirements
- [x] Clean separation between execution engine and UI
- [x] Proper async/await patterns throughout
- [x] Efficient dependency resolution
- [x] Scalable to larger graphs (10+ nodes)
- [x] Memory efficient artifact storage

### User Experience
- [x] Clear visual feedback during execution
- [x] Easy access to run history and results
- [x] Intuitive error messages
- [x] Fast execution for mock operations
- [x] Smooth animations and transitions

---

## Implementation Order

1. **Week 1**: Run & Artifact models + basic persistence
2. **Week 2**: Execution engine core + topological sorting
3. **Week 3**: Mock adapter + node-specific logic
4. **Week 4**: Run history UI + status indicators
5. **Week 5**: Integration + testing + polish

---

## Next Steps for New Conversation

1. **Start with Run & Artifact models** - these are the foundation
2. **Create a simple test** - execute a single TextPrompt node
3. **Build incrementally** - add one node type at a time
4. **Focus on the happy path first** - error handling can come later
5. **Keep UI simple initially** - focus on functionality over polish

## Key Files to Create/Modify

### New Files
- `RunModels.swift` - Run, Artifact, RunArtifact, ModelRef
- `ExecutionEngine.swift` - Core execution logic
- `MockAdapter.swift` - Mock cloud provider
- `RunHistoryView.swift` - Run history UI
- `ArtifactManager.swift` - File storage and management

### Modified Files
- `GraphCore.swift` - Add execution-related methods
- `ContentView.swift` - Add execution triggers
- `NodeViews.swift` - Add run status indicators

---

## Questions to Consider

1. **Persistence**: Core Data vs SQLite vs simple JSON files?
2. **Artifact Storage**: Local only vs cloud storage integration?
3. **Execution Strategy**: Immediate vs batched execution?
4. **Error Recovery**: Retry vs manual restart?
5. **Performance**: How to handle large graphs efficiently?

This plan gives you a solid foundation for Phase 2. Start the new conversation with this context and begin with the Run & Artifact models!
