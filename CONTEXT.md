## Dio — App Context (Business + Product)

### One-liner
Dio is a touch-first node editor for iOS that lets people compose simple AI workflows on a freeform canvas and generate images and videos from prompts.

### Problem
- Fragmented AI tasks: Prompting, refining, and combining outputs across apps is clumsy on mobile.
- Linear UIs don’t fit creative iteration: Creators need visual branching, quick retries, and remixing.
- High setup cost: Most tools assume desktop, complex SDKs, or scripting knowledge.

### Solution
- Freeform canvas with movable "nodes" that represent actions (e.g., Text Prompt → Image Gen → Video Gen).
- Type-safe connections to guide users and prevent invalid flows.
- Local-first authoring with optional cloud adapters for heavy generation.

### Who it’s for
- Mobile-first creators: Short-form video/image creators ideating on the go.

### Core Jobs-To-Be-Done
- Capture a prompt idea and quickly see visual output.
- Iterate on variations (seeds/parameters) and keep a visual history.
- Combine nodes to form repeatable mini-pipelines (prompt → image → video).

### Product Principles
- Touch-native: Gestures feel like Freeform/Notes; no precision required.
- Start tiny, show results fast: Working mocks before real APIs.
- UI-agnostic engine: Graph logic independent from SwiftUI views.
- Resilient by default: Debounce, cancellation, clear error states.

### Version 1 (Scope)
- Canvas with pan/zoom and draggable node cards.
- Three initial nodes: Text Prompt, Image Gen (mock), Video Gen (stub).
- Basic connections and validation; simple run loop with progress.
- Local JSON persistence (auto-save last project; import/export later).

### Out of Scope (for now)
- Multi-user collaboration, real-time sync.
- Desktop/iPad parity, external keyboard shortcuts.
- Advanced schedulers, large-graph performance optimizations, Metal rendering.
- Full asset management beyond thumbnails and recent outputs.

### Value Proposition
- Speed: Go from idea → visual in seconds on a phone.
- Clarity: The graph shows what’s connected and why a result changed.
- Extensibility: Swap mock backends with real services behind interfaces.

### Metrics of Success
- Time-to-first-output < 60s for new users.
- Repeat usage: 3+ sessions in first week per active user.
- 70% task success on connecting two nodes without guidance.
- Crash-free sessions > 99.5%.

### Risks & Mitigations
- Gesture conflicts → Background pan, high-priority node drag, haptics cues.
- API variability/latency → Start with mocks/stubs; adapters; retries + backoff.
- On-device performance → Draw only in viewport; debounce layout/work.

### Privacy & Data
- Store graphs locally; no data sent unless user opts into external services.
- API keys kept in Keychain; clear network indicator when remote services used.

### Naming & Terminology
- Node: A unit of work (e.g., Text Prompt, Image Gen).
- Port: A typed input or output on a node (text, image, video, number, json).
- Edge: A connection from an output port to an input port.
- Graph: The set of nodes and edges on the canvas.
- Viewport: Canvas transform (scale, offset) for pan/zoom.

### Competitive Notes
- Diagramming apps (Freeform, Muse) lack executable nodes.
- Workflow apps (Shortcuts) aren’t touch-first for creative media iteration.
- Pro AI tools assume desktop; Dio focuses on fast mobile ideation.

### Future Directions (post-v1)
- Project list with snapshots; asset bundling (zip export/import).
- Palette search, alignment guides, multi-select, undo/redo across gestures.
- Real image/video adapters; cloud render queue; shareable links.

---
Owner: Varick
Status: Draft (living document)
Last updated: 2025-09-18
