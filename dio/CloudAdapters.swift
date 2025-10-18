import Foundation
import Combine
import FalClient
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Cloud Adapter Protocol

public protocol CloudAdapter {
    var provider: String { get }
    var isAvailable: Bool { get }
    
    func invoke(_ request: InvocationRequest) async throws -> InvocationResponse
    func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse
    func cancel(jobID: String, credentialID: UUID) async throws -> Bool
}

// MARK: - Invocation Request/Response Models

public struct InvocationRequest: Codable {
    public let model: ModelRef
    public let params: JSONValue
    public let files: [URL]?
    public let runKey: String
    public let credentialID: UUID
    public let timeout: TimeInterval?
    
    public init(
        model: ModelRef,
        params: JSONValue,
        files: [URL]? = nil,
        runKey: String,
        credentialID: UUID,
        timeout: TimeInterval? = nil
    ) {
        self.model = model
        self.params = params
        self.files = files
        self.runKey = runKey
        self.credentialID = credentialID
        self.timeout = timeout
    }
}

public struct InvocationResponse: Codable {
    public let status: String
    public let outputs: JSONValue?
    public let artifacts: [ArtifactRef]?
    public let errorCode: String?
    public let errorMessage: String?
    public let billedUSD: Decimal?
    public let vendorMeta: JSONValue?
    public let jobID: String?
    
    public init(
        status: String,
        outputs: JSONValue? = nil,
        artifacts: [ArtifactRef]? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        billedUSD: Decimal? = nil,
        vendorMeta: JSONValue? = nil,
        jobID: String? = nil
    ) {
        self.status = status
        self.outputs = outputs
        self.artifacts = artifacts
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.billedUSD = billedUSD
        self.vendorMeta = vendorMeta
        self.jobID = jobID
    }
}

public struct ArtifactRef: Codable {
    public let kind: String
    public let mimeType: String
    public let uri: String
    public let sizePx: CGSize?
    public let durationSec: Float?
    public let metadata: JSONValue?
    
    public init(
        kind: String,
        mimeType: String,
        uri: String,
        sizePx: CGSize? = nil,
        durationSec: Float? = nil,
        metadata: JSONValue? = nil
    ) {
        self.kind = kind
        self.mimeType = mimeType
        self.uri = uri
        self.sizePx = sizePx
        self.durationSec = durationSec
        self.metadata = metadata
    }
}

// MARK: - Adapter Registry

public class AdapterRegistry: ObservableObject {
    public static let shared = AdapterRegistry()
    
    private var adapters: [String: CloudAdapter] = [:]
    
    private init() {
        registerDefaultAdapters()
    }
    
    public func register(_ adapter: CloudAdapter) {
        adapters[adapter.provider] = adapter
    }
    
    public func getAdapter(for provider: String) -> CloudAdapter? {
        return adapters[provider]
    }
    
    public func getAvailableAdapters() -> [CloudAdapter] {
        return adapters.values.filter { $0.isAvailable }
    }
    
    private func registerDefaultAdapters() {
        register(MockAdapter())
        register(FALAdapter())
        register(OpenAIAdapter())
        // Future: register(WaveSpeedAdapter())
    }
}

// MARK: - Mock Adapter

public class MockAdapter: CloudAdapter {
    public let provider = "Mock"
    public let isAvailable = true
    
    private let artifactManager = ArtifactManager.shared
    private let persistence = RunPersistence.shared
    private var activeJobs: [String: MockJob] = [:]
    private let jobQueue = DispatchQueue(label: "mock.jobs", attributes: .concurrent)
    
    public init() {}
    
    // MARK: - CloudAdapter Protocol
    
    public func invoke(_ request: InvocationRequest) async throws -> InvocationResponse {
        // Simulate network delay
        let networkDelay = Double.random(in: 0.1...0.5)
        try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Determine if this should be async or sync
        let isAsync = request.model.mode == "async" && shouldUseAsync(for: request.model.modelID)
        
        if isAsync {
            return try await handleAsyncInvocation(request)
        } else {
            return try await handleSyncInvocation(request)
        }
    }
    
    public func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse {
        // Simulate polling delay
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds
        
        return try jobQueue.sync {
            guard let job = activeJobs[jobID] else {
                print("MockAdapter: Job not found: \(jobID)")
                throw AdapterError.jobNotFound(jobID)
            }
            
            print("MockAdapter: Polling job \(jobID), completed: \(job.isCompleted)")
            
            if job.isCompleted {
                activeJobs.removeValue(forKey: jobID)
                print("MockAdapter: Job \(jobID) completed, returning response")
                return job.response
            } else {
                print("MockAdapter: Job \(jobID) still running")
                return InvocationResponse(
                    status: "running",
                    jobID: jobID
                )
            }
        }
    }
    
    public func cancel(jobID: String, credentialID: UUID) async throws -> Bool {
        return try jobQueue.sync {
            guard let job = activeJobs[jobID] else {
                return false
            }
            
            job.cancel()
            activeJobs.removeValue(forKey: jobID)
            return true
        }
    }
    
    // MARK: - Private Methods
    
    private func shouldUseAsync(for modelID: String) -> Bool {
        // Some models are always async (e.g., video generation)
        return modelID.contains("video") || modelID.contains("async")
    }
    
    private func handleSyncInvocation(_ request: InvocationRequest) async throws -> InvocationResponse {
        // Simulate processing time based on model type
        let processingTime = getProcessingTime(for: request.model.modelID)
        try await Task.sleep(nanoseconds: UInt64(processingTime * 1_000_000_000))
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Generate response based on model type
        return try await generateResponse(for: request)
    }
    
    private func handleAsyncInvocation(_ request: InvocationRequest) async throws -> InvocationResponse {
        let jobID = "mock_\(UUID().uuidString)"
        
        // Create async job
        let job = MockJob(
            id: jobID,
            request: request,
            processingTime: getProcessingTime(for: request.model.modelID)
        )
        
        jobQueue.sync(flags: .barrier) {
            self.activeJobs[jobID] = job
        }
        
        // Start processing in background
        Task {
            do {
                print("MockAdapter: Starting async processing for job \(jobID)")
                let response = try await self.processAsyncJob(job)
                await self.jobQueue.sync(flags: .barrier) {
                    job.response = response
                    job.isCompleted = true
                    print("MockAdapter: Job \(jobID) completed successfully")
                }
            } catch {
                print("MockAdapter: Job \(jobID) failed with error: \(error)")
                await self.jobQueue.sync(flags: .barrier) {
                    job.response = InvocationResponse(
                        status: "failed",
                        errorCode: "PROCESSING_ERROR",
                        errorMessage: error.localizedDescription
                    )
                    job.isCompleted = true
                }
            }
        }
        
        return InvocationResponse(
            status: "queued",
            jobID: jobID
        )
    }
    
    private func processAsyncJob(_ job: MockJob) async throws -> InvocationResponse {
        print("MockAdapter: Processing job \(job.id) for \(job.processingTime) seconds")
        
        // Simulate processing time
        try await Task.sleep(nanoseconds: UInt64(job.processingTime * 1_000_000_000))
        
        // Check for cancellation
        try Task.checkCancellation()
        
        print("MockAdapter: Generating response for job \(job.id)")
        
        // Generate response
        return try await generateResponse(for: job.request)
    }
    
    private func generateResponse(for request: InvocationRequest) async throws -> InvocationResponse {
        let modelID = request.model.modelID
        
        // Simulate occasional failures (5% chance)
        if Double.random(in: 0...1) < 0.05 {
            return InvocationResponse(
                status: "failed",
                errorCode: "MOCK_ERROR",
                errorMessage: "Simulated mock error for testing",
                billedUSD: Decimal(0.001)
            )
        }
        
        switch modelID {
        case let id where id.contains("image") || id.contains("sdxl") || id.contains("flux"):
            return try await generateImageResponse(request)
            
        case let id where id.contains("video"):
            if modelID.contains("video_concat") {
                return try await generateVideoConcatResponse(request)
            }
            return try await generateVideoResponse(request)
            
        case let id where id.contains("async"):
            return try await generateAsyncResponse(request)
            
        default:
            return try await generateGenericResponse(request)
        }
    }
    
    
    private func generateImageResponse(_ request: InvocationRequest) async throws -> InvocationResponse {
        let prompt = request.params.get("/prompt", as: String.self) ?? "Generated image"
        let width = request.params.get("/size/width", as: Double.self) ?? 512
        let height = request.params.get("/size/height", as: Double.self) ?? 512
        let size = CGSize(width: width, height: height)
        
        // Generate mock image
        let imageData = generateMockImageData(prompt: prompt, size: size)
        let artifact = try artifactManager.storeArtifact(
            data: imageData,
            kind: "image",
            mimeType: "image/png",
            sizePx: size
        )
        
        return InvocationResponse(
            status: "succeeded",
            outputs: .object([
                "image_count": .number(1),
                "size": .object([
                    "width": .number(width),
                    "height": .number(height)
                ])
            ]),
            artifacts: [
                ArtifactRef(
                    kind: "image",
                    mimeType: "image/png",
                    uri: artifact.uri,
                    sizePx: size,
                    metadata: .object([
                        "prompt": .string(prompt)
                    ])
                )
            ],
            billedUSD: Decimal(0.0015)
        )
    }
    
    private func generateVideoResponse(_ request: InvocationRequest) async throws -> InvocationResponse {
        let prompt = request.params.get("/prompt", as: String.self) ?? "Generated video"
        let duration = request.params.get("/seconds", as: Double.self) ?? (request.params.get("/duration", as: Double.self) ?? 5.0)
        
        // Generate mock video
        let videoData = generateMockVideoData(prompt: prompt, duration: Float(duration))
        let artifact = try artifactManager.storeArtifact(
            data: videoData,
            kind: "video",
            mimeType: "video/mp4",
            durationSec: Float(duration)
        )
        
        return InvocationResponse(
            status: "succeeded",
            outputs: .object([
                "video_count": .number(1),
                "duration": .number(duration)
            ]),
            artifacts: [
                ArtifactRef(
                    kind: "video",
                    mimeType: "video/mp4",
                    uri: artifact.uri,
                    durationSec: Float(duration),
                    metadata: .object([
                        "prompt": .string(prompt)
                    ])
                )
            ],
            billedUSD: Decimal(0.01)
        )
    }
    
    private func generateAsyncResponse(_ request: InvocationRequest) async throws -> InvocationResponse {
        let task = request.params.get("/task", as: String.self) ?? "Unknown task"
        let complexity = request.params.get("/complexity", as: Double.self) ?? 1.0
        
        // Generate mock async processing result
        let result = generateMockAsyncResult(for: task, complexity: complexity)
        
        return InvocationResponse(
            status: "succeeded",
            outputs: .object([
                "task": .string(task),
                "result": .string(result),
                "complexity": .number(complexity),
                "processingTime": .number(Date().timeIntervalSince1970),
                "status": .string("completed")
            ]),
            billedUSD: Decimal(0.005)
        )
    }
    
    private func generateGenericResponse(_ request: InvocationRequest) async throws -> InvocationResponse {
        return InvocationResponse(
            status: "succeeded",
            outputs: .object([
                "result": .string("Mock response for \(request.model.modelID)"),
                "timestamp": .number(Date().timeIntervalSince1970)
            ]),
            billedUSD: Decimal(0.001)
        )
    }

    // MARK: - Local Video Concat (AVFoundation)
    private func generateVideoConcatResponse(_ request: InvocationRequest) async throws -> InvocationResponse {
        // Gather up to 4 input video URLs
        var uris: [String] = []
        if let v1: String = request.params.get("/video_url_1", as: String.self), !v1.isEmpty { uris.append(v1) }
        if let v2: String = request.params.get("/video_url_2", as: String.self), !v2.isEmpty { uris.append(v2) }
        if let v3: String = request.params.get("/video_url_3", as: String.self), !v3.isEmpty { uris.append(v3) }
        if let v4: String = request.params.get("/video_url_4", as: String.self), !v4.isEmpty { uris.append(v4) }
        let inputURLs = uris.compactMap { URL(string: $0) }
        guard !inputURLs.isEmpty else {
            return InvocationResponse(
                status: "failed",
                errorCode: "NO_INPUT",
                errorMessage: "No input videos provided for concat"
            )
        }
        
        let outputURL = try await concatenateVideos(inputURLs: inputURLs)
        let data = try Data(contentsOf: outputURL)
        let artifact = try artifactManager.storeArtifact(
            data: data,
            kind: "video",
            mimeType: "video/mp4"
        )
        persistence.storeArtifact(artifact)
        
        return InvocationResponse(
            status: "succeeded",
            outputs: .object([
                "video_count": .number(1),
                "parts": .number(Double(inputURLs.count))
            ]),
            artifacts: [
                ArtifactRef(
                    kind: "video",
                    mimeType: "video/mp4",
                    uri: artifact.uri
                )
            ],
            billedUSD: Decimal(0)
        )
    }

    private func concatenateVideos(inputURLs: [URL]) async throws -> URL {
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var currentTime = CMTime.zero
        
        for url in inputURLs {
            let asset = AVURLAsset(url: url)
        let vTracks = try await asset.loadTracks(withMediaType: .video)
        if let srcVideo = vTracks.first {
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
                try videoTrack?.insertTimeRange(timeRange, of: srcVideo, at: currentTime)
            }
        let aTracks = try await asset.loadTracks(withMediaType: .audio)
        if let srcAudio = aTracks.first {
            let duration = try await asset.load(.duration)
            let timeRange = CMTimeRange(start: .zero, duration: duration)
                try audioTrack?.insertTimeRange(timeRange, of: srcAudio, at: currentTime)
            }
        currentTime = currentTime + (try await asset.load(.duration))
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let outURL = tempDir.appendingPathComponent("concat_\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: outURL.path) {
            try? FileManager.default.removeItem(at: outURL)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw AdapterError.invalidRequest("Failed to create export session")
        }
        exporter.outputURL = outURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true

        if #available(iOS 18.0, *) {
            // Use new async exporting API
            try await exporter.export(to: outURL, as: .mpeg4Movie)
            return outURL
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                exporter.exportAsynchronously {
                    switch exporter.status {
                    case .completed:
                        continuation.resume(returning: outURL)
                    case .failed, .cancelled:
                        continuation.resume(throwing: AdapterError.invalidRequest(exporter.error?.localizedDescription ?? "Export failed"))
                    default:
                        break
                    }
                }
            }
        }
    }
    
    // MARK: - Mock Data Generation
    
    
    private func generateMockImageData(prompt: String, size: CGSize) -> Data {
        // Create a simple colored rectangle based on the prompt
        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        var pixelData = Data(count: totalBytes)
        
        // Generate colors based on prompt hash
        let promptHash = prompt.hashValue
        let r = UInt8(abs(promptHash) % 256)
        let g = UInt8(abs(promptHash >> 8) % 256)
        let b = UInt8(abs(promptHash >> 16) % 256)
        
        for i in 0..<totalBytes {
            if i % 4 == 0 { // Red channel
                pixelData[i] = r
            } else if i % 4 == 1 { // Green channel
                pixelData[i] = g
            } else if i % 4 == 2 { // Blue channel
                pixelData[i] = b
            } else { // Alpha channel
                pixelData[i] = 255
            }
        }
        
        return pixelData
    }
    
    private func generateMockVideoData(prompt: String, duration: Float) -> Data {
        // Create a simple video file header (mock)
        var data = Data()
        
        // Add a simple header
        data.append("MOCK_VIDEO".data(using: .utf8)!)
        data.append(prompt.data(using: .utf8)!)
        data.append(Data([UInt8(duration)]))
        
        // Add some padding to simulate video data
        let paddingSize = Int(duration * 1000) // 1KB per second
        data.append(Data(count: paddingSize))
        
        return data
    }
    
    private func generateMockAsyncResult(for task: String, complexity: Double) -> String {
        let templates = [
            "Successfully processed '\(task)' with complexity \(complexity). Generated comprehensive analysis and insights.",
            "Completed complex processing of '\(task)'. Results include detailed breakdown and recommendations.",
            "Finished async processing for '\(task)'. Generated structured output with \(Int(complexity * 10)) data points.",
            "Async operation completed for '\(task)'. Produced optimized results based on complexity level \(complexity)."
        ]
        
        return templates.randomElement() ?? "Async processing completed for: \(task)"
    }
    
    private func getProcessingTime(for modelID: String) -> Double {
        if modelID.contains("video") {
            return Double.random(in: 5.0...15.0) // Video generation takes longer
        } else if modelID.contains("image") {
            return Double.random(in: 1.0...3.0) // Image generation
        } else if modelID.contains("async") {
            return Double.random(in: 2.0...4.0) // Async processing
        } else {
            return Double.random(in: 0.5...1.5) // Text generation
        }
    }
}

// MARK: - FAL Adapter moved to FALAdapter.swift
// MARK: - Mock Job

private class MockJob {
    let id: String
    let request: InvocationRequest
    let processingTime: Double
    var response: InvocationResponse
    var isCompleted: Bool = false
    private var isCancelled: Bool = false
    
    init(id: String, request: InvocationRequest, processingTime: Double) {
        self.id = id
        self.request = request
        self.processingTime = processingTime
        self.response = InvocationResponse(status: "queued", jobID: id)
    }
    
    func cancel() {
        isCancelled = true
        response = InvocationResponse(
            status: "cancelled",
            errorCode: "CANCELLED",
            errorMessage: "Job was cancelled by user"
        )
        isCompleted = true
    }
}

// MARK: - Adapter Errors

public enum AdapterError: Error, LocalizedError {
    case jobNotFound(String)
    case timeout(String)
    case invalidCredentials
    case rateLimitExceeded
    case serviceUnavailable
    case invalidRequest(String)
    
    public var errorDescription: String? {
        switch self {
        case .jobNotFound(let jobID):
            return "Job not found: \(jobID)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .invalidCredentials:
            return "Invalid credentials provided"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .serviceUnavailable:
            return "Service is currently unavailable"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        }
    }
}

// MARK: - JSONValue Extensions

extension JSONValue {
    func get<T>(_ path: String, as type: T.Type) -> T? {
        let pointer = JSONPointer(path)
        guard let value = pointer.get(from: self) else { return nil }
        
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
    
    /// Converts JSONValue to a readable string representation
    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .null:
            return "null"
        case .array(let values):
            let items = values.map { $0.displayString }.joined(separator: ", ")
            return "[\(items)]"
        case .object(let dict):
            let pairs = dict.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", ")
            return "{\(pairs)}"
        }
    }
}
