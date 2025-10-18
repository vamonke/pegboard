import Foundation
import XCTest

// MARK: - Mock Adapter Tests

class MockAdapterTests: XCTestCase {
    
    var mockAdapter: MockAdapter!
    var adapterRegistry: AdapterRegistry!
    
    override func setUp() {
        super.setUp()
        mockAdapter = MockAdapter()
        adapterRegistry = AdapterRegistry.shared
    }
    
    // MARK: - Basic Adapter Tests
    
    func testAdapterProperties() {
        XCTAssertEqual(mockAdapter.provider, "Mock")
        XCTAssertTrue(mockAdapter.isAvailable)
    }
    
    func testAdapterRegistry() {
        let adapters = adapterRegistry.getAvailableAdapters()
        XCTAssertFalse(adapters.isEmpty)
        
        let mockAdapter = adapterRegistry.getAdapter(for: "Mock")
        XCTAssertNotNil(mockAdapter)
        XCTAssertEqual(mockAdapter?.provider, "Mock")
    }
    
    // MARK: - Text Generation Tests
    
    func testTextGeneration() async throws {
        let request = InvocationRequest(
            model: ModelRef(
                provider: "Mock",
                modelID: "text-generator",
                endpoint: "/text/generate"
            ),
            params: .object([
                "prompt": .string("Test prompt for text generation")
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let response = try await mockAdapter.invoke(request)
        
        XCTAssertEqual(response.status, "succeeded")
        XCTAssertNotNil(response.outputs)
        XCTAssertNotNil(response.artifacts)
        XCTAssertEqual(response.artifacts?.count, 1)
        XCTAssertEqual(response.artifacts?.first?.kind, "text")
        XCTAssertNotNil(response.billedUSD)
    }
    
    // MARK: - Image Generation Tests
    
    func testImageGeneration() async throws {
        let request = InvocationRequest(
            model: ModelRef(
                provider: "Mock",
                modelID: "image-generator",
                endpoint: "/image/generate"
            ),
            params: .object([
                "prompt": .string("A beautiful sunset"),
                "size": .object([
                    "width": .number(512),
                    "height": .number(512)
                ])
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let response = try await mockAdapter.invoke(request)
        
        XCTAssertEqual(response.status, "succeeded")
        XCTAssertNotNil(response.outputs)
        XCTAssertNotNil(response.artifacts)
        XCTAssertEqual(response.artifacts?.count, 1)
        XCTAssertEqual(response.artifacts?.first?.kind, "image")
        XCTAssertEqual(response.artifacts?.first?.mimeType, "image/png")
        XCTAssertNotNil(response.artifacts?.first?.sizePx)
        XCTAssertNotNil(response.billedUSD)
    }
    
    // MARK: - Video Generation Tests
    
    func testOpenaiSora() async throws {
        let request = InvocationRequest(
            model: ModelRef(
                provider: "Mock",
                modelID: "video-generator",
                endpoint: "/video/generate"
            ),
            params: .object([
                "prompt": .string("A time-lapse video"),
                "duration": .number(5.0)
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let response = try await mockAdapter.invoke(request)
        
        XCTAssertEqual(response.status, "succeeded")
        XCTAssertNotNil(response.outputs)
        XCTAssertNotNil(response.artifacts)
        XCTAssertEqual(response.artifacts?.count, 1)
        XCTAssertEqual(response.artifacts?.first?.kind, "video")
        XCTAssertEqual(response.artifacts?.first?.mimeType, "video/mp4")
        XCTAssertNotNil(response.artifacts?.first?.durationSec)
        XCTAssertNotNil(response.billedUSD)
    }
    
    // MARK: - Async Operation Tests
    
    func testAsyncOperation() async throws {
        let request = InvocationRequest(
            model: ModelRef(
                provider: "Mock",
                modelID: "async-processor",
                endpoint: "/process",
                mode: "async"
            ),
            params: .object([
                "task": .string("Complex processing")
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let initialResponse = try await mockAdapter.invoke(request)
        
        XCTAssertEqual(initialResponse.status, "queued")
        XCTAssertNotNil(initialResponse.jobID)
        
        // Poll for completion
        let jobID = initialResponse.jobID!
        var pollCount = 0
        let maxPolls = 20
        
        while pollCount < maxPolls {
            let pollResponse = try await mockAdapter.poll(jobID: jobID, credentialID: UUID())
            
            if pollResponse.status == "succeeded" {
                XCTAssertNotNil(pollResponse.outputs)
                XCTAssertNotNil(pollResponse.billedUSD)
                return
            } else if pollResponse.status == "failed" {
                XCTFail("Async operation failed: \(pollResponse.errorMessage ?? "Unknown error")")
                return
            }
            
            // Wait before next poll
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            pollCount += 1
        }
        
        XCTFail("Async operation timed out")
    }
    
    // MARK: - Error Simulation Tests
    
    func testErrorSimulation() async throws {
        // Run multiple requests to increase chance of hitting the 5% error rate
        var errorCount = 0
        let totalRequests = 50
        
        for _ in 0..<totalRequests {
            let request = InvocationRequest(
                model: ModelRef(
                    provider: "Mock",
                    modelID: "error-generator",
                    endpoint: "/test"
                ),
                params: .object([
                    "prompt": .string("Test prompt")
                ]),
                runKey: ULID.generate(),
                credentialID: UUID()
            )
            
            let response = try await mockAdapter.invoke(request)
            
            if response.status == "failed" {
                errorCount += 1
                XCTAssertNotNil(response.errorCode)
                XCTAssertNotNil(response.errorMessage)
            }
        }
        
        // Should have some errors (around 5% of requests)
        XCTAssertGreaterThan(errorCount, 0)
        print("Error rate: \(Double(errorCount) / Double(totalRequests) * 100)%")
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellation() async throws {
        let request = InvocationRequest(
            model: ModelRef(
                provider: "Mock",
                modelID: "long-running-task",
                endpoint: "/process",
                mode: "async"
            ),
            params: .object([
                "task": .string("Long running task")
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let initialResponse = try await mockAdapter.invoke(request)
        XCTAssertEqual(initialResponse.status, "queued")
        
        let jobID = initialResponse.jobID!
        
        // Cancel the job
        let cancelled = try await mockAdapter.cancel(jobID: jobID, credentialID: UUID())
        XCTAssertTrue(cancelled)
        
        // Try to poll the cancelled job
        let pollResponse = try await mockAdapter.poll(jobID: jobID, credentialID: UUID())
        XCTAssertEqual(pollResponse.status, "cancelled")
    }
    
    // MARK: - Cost Calculation Tests
    
    func testCostCalculation() async throws {
        let textRequest = InvocationRequest(
            model: ModelRef(provider: "Mock", modelID: "text-generator", endpoint: "/text"),
            params: .object(["prompt": .string("Test")]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let imageRequest = InvocationRequest(
            model: ModelRef(provider: "Mock", modelID: "image-generator", endpoint: "/image"),
            params: .object(["prompt": .string("Test")]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let videoRequest = InvocationRequest(
            model: ModelRef(provider: "Mock", modelID: "video-generator", endpoint: "/video"),
            params: .object(["prompt": .string("Test")]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let textResponse = try await mockAdapter.invoke(textRequest)
        let imageResponse = try await mockAdapter.invoke(imageRequest)
        let videoResponse = try await mockAdapter.invoke(videoRequest)
        
        XCTAssertNotNil(textResponse.billedUSD)
        XCTAssertNotNil(imageResponse.billedUSD)
        XCTAssertNotNil(videoResponse.billedUSD)
        
        // Video should cost more than image, image more than text
        let textCost = textResponse.billedUSD ?? 0
        let imageCost = imageResponse.billedUSD ?? 0
        let videoCost = videoResponse.billedUSD ?? 0
        
        XCTAssertGreaterThan(imageCost, textCost)
        XCTAssertGreaterThan(videoCost, imageCost)
    }
    
    // MARK: - Processing Time Tests
    
    func testProcessingTimes() async throws {
        let startTime = Date()
        
        let request = InvocationRequest(
            model: ModelRef(provider: "Mock", modelID: "image-generator", endpoint: "/image"),
            params: .object(["prompt": .string("Test")]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        _ = try await mockAdapter.invoke(request)
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        // Should take at least 1 second (minimum processing time for images)
        XCTAssertGreaterThan(duration, 1.0)
        // Should not take more than 5 seconds (maximum processing time + network delay)
        XCTAssertLessThan(duration, 5.0)
    }
    
    // MARK: - Artifact Generation Tests
    
    func testArtifactGeneration() async throws {
        let request = InvocationRequest(
            model: ModelRef(provider: "Mock", modelID: "image-generator", endpoint: "/image"),
            params: .object([
                "prompt": .string("Test image"),
                "size": .object([
                    "width": .number(1024),
                    "height": .number(768)
                ])
            ]),
            runKey: ULID.generate(),
            credentialID: UUID()
        )
        
        let response = try await mockAdapter.invoke(request)
        
        XCTAssertEqual(response.status, "succeeded")
        XCTAssertNotNil(response.artifacts)
        XCTAssertEqual(response.artifacts?.count, 1)
        
        let artifact = response.artifacts!.first!
        XCTAssertEqual(artifact.kind, "image")
        XCTAssertEqual(artifact.mimeType, "image/png")
        XCTAssertEqual(artifact.sizePx?.width, 1024)
        XCTAssertEqual(artifact.sizePx?.height, 768)
        XCTAssertNotNil(artifact.metadata)
    }
    
    // MARK: - Concurrent Request Tests
    
    func testConcurrentRequests() async throws {
        let requests = (0..<10).map { i in
            InvocationRequest(
                model: ModelRef(provider: "Mock", modelID: "text-generator", endpoint: "/text"),
                params: .object(["prompt": .string("Concurrent test \(i)")]),
                runKey: ULID.generate(),
                credentialID: UUID()
            )
        }
        
        let startTime = Date()
        
        // Execute all requests concurrently
        let responses = try await withThrowingTaskGroup(of: InvocationResponse.self) { group in
            for request in requests {
                group.addTask {
                    try await self.mockAdapter.invoke(request)
                }
            }
            
            var results: [InvocationResponse] = []
            for try await response in group {
                results.append(response)
            }
            return results
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        XCTAssertEqual(responses.count, 10)
        XCTAssertTrue(responses.allSatisfy { $0.status == "succeeded" })
        
        // Should complete faster than sequential execution
        XCTAssertLessThan(duration, 10.0)
        print("Concurrent execution time: \(duration)s")
    }
}
