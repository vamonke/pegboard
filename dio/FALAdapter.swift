import Foundation
import FalClient

// MARK: - FAL Adapter (Minimal subscribe-based)

public class FALAdapter: CloudAdapter {
    public let provider = "FAL"
    public var isAvailable: Bool { true }
    
    private let artifactManager = ArtifactManager.shared
    private let persistence = RunPersistence.shared
    private let jobsQueue = DispatchQueue(label: "fal.adapter.jobs", attributes: .concurrent)
    private var activeJobs: [String: Task<InvocationResponse, Never>] = [:]
    private var jobLogs: [String: [String]] = [:]
    private var completedJobResults: [String: InvocationResponse] = [:]
    
    public init() {}
    
    public func invoke(_ request: InvocationRequest) async throws -> InvocationResponse {
        // Map params to Payload expected by FalClient
        let input: Payload
        if request.model.modelID.contains("nano-banana/edit") {
            input = await buildNanoBananaEditInput(from: request.params)
        } else if request.model.modelID.contains("bytedance/seedream/v4/edit") {
            input = await buildSeedDreamV4EditInput(from: request.params)
        } else if request.model.modelID.contains("bytedance/seedance/v1/pro/image-to-video") {
            input = await buildSeedanceImageToVideoInput(from: request.params)
        } else if request.model.modelID.contains("kling-video") && request.model.modelID.contains("image-to-video") {
            input = await buildKlingImageToVideoInput(from: request.params)
        } else if request.model.modelID.contains("wan/v2.2-14b/animate/move") {
            input = await buildWanAnimateMoveInput(from: request.params)
        } else if request.model.modelID.contains("wan/v2.2-14b/animate/replace") {
            input = await buildWanAnimateMoveInput(from: request.params) // same schema as move
        } else {
            input = buildFluxInput(from: request.params)
        }
        
        // Extract original prompt for preservation in response
        let originalPrompt = request.params.get("/prompt", as: String.self) ?? ""
        
        // Use endpoint model id as the FAL model identifier (e.g. "fal-ai/flux/dev")
        let modelID = request.model.modelID
        
        // WAN models are long-running; run in background and return a jobID for polling/resume
        if modelID.contains("wan/") {
            let jobID = "fal_\(UUID().uuidString)"
            jobsQueue.async(flags: .barrier) {
                self.jobLogs[jobID] = []
            }

            let task: Task<InvocationResponse, Never>

            if modelID.contains("wan/v2.2-14b/animate/replace") {
                // Demo: short-circuit WAN replace to return a placeholder TEST_URL
                task = Task { [weak self] () -> InvocationResponse in
                    guard let self = self else { return InvocationResponse(status: "failed", errorCode: "INTERNAL", errorMessage: "Adapter deallocated") }
                    var collectedLogs: [String] = []
                    collectedLogs.append("Demo placeholder: WAN replace job started")
                    // brief delay to simulate work
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    collectedLogs.append("Demo placeholder: Generating TEST_URL artifact")
                    self.jobsQueue.async(flags: .barrier) {
                        self.jobLogs[jobID] = collectedLogs
                    }

                    let placeholderURL = "https://v3b.fal.media/files/b/elephant/A1aWFYijMNG7RNqyYAIhV_wan_animate_output.mp4"
                    // Create and store a remote placeholder artifact for linking in UI
                    let artifact = Artifact(
                        kind: "video",
                        mimeType: "video/mp4",
                        storage: "remote",
                        uri: placeholderURL,
                        contentHash: ContentHasher.hash(string: placeholderURL),
                        sizePx: nil,
                        durationSec: nil
                    )
                    self.persistence.storeArtifact(artifact)

                    let outputs: JSONValue = .object([
                        "prompt": .string(originalPrompt),
                        "video_url": .string(placeholderURL),
                        "status": .string("completed")
                    ])

                    let refs: [ArtifactRef] = [
                        ArtifactRef(
                            kind: "video",
                            mimeType: "video/mp4",
                            uri: artifact.uri,
                            sizePx: nil,
                            durationSec: nil,
                            metadata: .object([
                                "prompt": .string(originalPrompt),
                                "remote_uri": .string(artifact.uri),
                                "demo": .string("wan_replace_placeholder")
                            ])
                        )
                    ]

                    let vendorMeta: JSONValue = .object([
                        "logs": .array(collectedLogs.map { .string($0) }),
                        "progress": .number(100),
                        "demo": .string("wan_replace_placeholder")
                    ])

                    let response = InvocationResponse(
                        status: "succeeded",
                        outputs: outputs,
                        artifacts: refs,
                        billedUSD: nil,
                        vendorMeta: vendorMeta,
                        jobID: jobID
                    )
                    self.jobsQueue.async(flags: .barrier) {
                        self.completedJobResults[jobID] = response
                    }
                    return response
                }
            } else {
                task = Task { [weak self] () -> InvocationResponse in
                    guard let self = self else { return InvocationResponse(status: "failed", errorCode: "INTERNAL", errorMessage: "Adapter deallocated") }
                    var collectedLogs: [String] = []
                    do {
                        let result = try await fal.subscribe(
                            to: modelID,
                            input: input,
                            pollInterval: .seconds(1),
                            timeout: .minutes(15),
                            includeLogs: true,
                            onQueueUpdate: { update in
                                switch update {
                                case let .inProgress(logs):
                                    let logStrings = logs.map { String(describing: $0) }
                                    collectedLogs.append(contentsOf: logStrings)
                                    print("FAL[\(modelID)] logs: \(logStrings.joined(separator: " | "))")
                                default:
                                    let line = String(describing: update)
                                    collectedLogs.append(line)
                                    print("FAL[\(modelID)] queue update: \(line)")
                                }
                                self.jobsQueue.async(flags: .barrier) {
                                    self.jobLogs[jobID] = collectedLogs
                                }
                            }
                        )
                        let (artifacts, outputsMeta) = await self.extractArtifactsAndOutputs(from: result, originalPrompt: originalPrompt)
                        let vendorMeta: JSONValue = .object([
                            "result": self.payloadToJSONValue(result) ?? .null,
                            "logs": .array(collectedLogs.map { .string($0) })
                        ])
                        let response = InvocationResponse(
                            status: "succeeded",
                            outputs: outputsMeta,
                            artifacts: artifacts,
                            billedUSD: nil,
                            vendorMeta: vendorMeta,
                            jobID: jobID
                        )
                        self.jobsQueue.async(flags: .barrier) {
                            self.completedJobResults[jobID] = response
                        }
                        return response
                    } catch {
                        print("FAL subscribe error for model=\(modelID): \(error)")
                        let errorMeta: JSONValue = .object([
                            "error": .string(String(describing: error)),
                            "logs": .array(collectedLogs.map { .string($0) })
                        ])
                        let response = InvocationResponse(
                            status: "failed",
                            errorCode: "FAL_SUBSCRIBE_ERROR",
                            errorMessage: error.localizedDescription,
                            vendorMeta: errorMeta,
                            jobID: jobID
                        )
                        self.jobsQueue.async(flags: .barrier) {
                            self.completedJobResults[jobID] = response
                        }
                        return response
                    }
                }
            }

            jobsQueue.async(flags: .barrier) {
                self.activeJobs[jobID] = task
            }
            return InvocationResponse(status: "queued", outputs: .object(["progress": .number(0)]), artifacts: nil, errorCode: nil, errorMessage: nil, billedUSD: nil, vendorMeta: .object(["logs": .array([])]), jobID: jobID)
        }
        
        // Default path: subscribe and await result (shorter models)
        var collectedLogs: [String] = []
        let result: Payload
        do {
            result = try await fal.subscribe(
                to: modelID,
                input: input,
                pollInterval: .seconds(1),
                timeout: .minutes(5),
                includeLogs: true,
                onQueueUpdate: { update in
                    switch update {
                    case let .inProgress(logs):
                        let logStrings = logs.map { String(describing: $0) }
                        collectedLogs.append(contentsOf: logStrings)
                        print("FAL[\(modelID)] logs: \(logStrings.joined(separator: " | "))")
                    default:
                        let line = String(describing: update)
                        collectedLogs.append(line)
                        print("FAL[\(modelID)] queue update: \(line)")
                    }
                }
            )
        } catch {
            print("FAL subscribe error for model=\(modelID): \(error)")
            let errorMeta: JSONValue = .object([
                "error": .string(String(describing: error)),
                "logs": .array(collectedLogs.map { .string($0) })
            ])
            return InvocationResponse(
                status: "failed",
                errorCode: "FAL_SUBSCRIBE_ERROR",
                errorMessage: error.localizedDescription,
                vendorMeta: errorMeta
            )
        }
        let (artifacts, outputsMeta) = await extractArtifactsAndOutputs(from: result, originalPrompt: originalPrompt)
        let vendorMeta: JSONValue = .object([
            "result": payloadToJSONValue(result) ?? .null,
            "logs": .array(collectedLogs.map { .string($0) })
        ])
        return InvocationResponse(
            status: "succeeded",
            outputs: outputsMeta,
            artifacts: artifacts,
            billedUSD: nil,
            vendorMeta: vendorMeta,
            jobID: nil
        )
    }
    
    public func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse {
        // Report current state for WAN background jobs
        let task: Task<InvocationResponse, Never>?
        let logs: [String]
        task = jobsQueue.sync { activeJobs[jobID] }
        logs = jobsQueue.sync { jobLogs[jobID] ?? [] }
        // First, check if the job has already completed without awaiting the Task
        if let finished = jobsQueue.sync(execute: { completedJobResults.removeValue(forKey: jobID) }) {
            jobsQueue.async(flags: .barrier) {
                self.activeJobs.removeValue(forKey: jobID)
            }
            return finished
        }
        if let task = task {
            if task.isCancelled {
                return InvocationResponse(status: "cancelled", vendorMeta: .object(["logs": .array(logs.map { .string($0) })]), jobID: jobID)
            }
            // Task still running
            return InvocationResponse(status: "running", outputs: .object(["progress": .number(0)]), vendorMeta: .object(["logs": .array(logs.map { .string($0) })]), jobID: jobID)
        }
        // Unknown job; treat as not found
        return InvocationResponse(status: "failed", errorCode: "JOB_NOT_FOUND", errorMessage: "Unknown job id", vendorMeta: .object(["logs": .array(logs.map { .string($0) })]), jobID: jobID)
    }
    
    public func cancel(jobID: String, credentialID: UUID) async throws -> Bool {
        var cancelled = false
        jobsQueue.sync {
            if let task = activeJobs[jobID] {
                task.cancel()
                cancelled = true
            }
        }
        if cancelled {
            jobsQueue.async(flags: .barrier) {
                self.activeJobs.removeValue(forKey: jobID)
            }
        }
        return cancelled
    }
    
    // MARK: - Helpers
    
    private func buildNanoBananaEditInput(from params: JSONValue) async -> Payload {
        // Extract supported fields with fallbacks
        let prompt = params.get("/prompt", as: String.self) ?? ""
        let numImages = params.get("/num_images", as: Int.self) ?? 1
        let outputFormat = params.get("/output_format", as: String.self) ?? "jpeg"
        
        // Extract image URLs from the params
        var imageUrls: [String] = []
        let pointer = JSONPointer("/image_urls")
        if case .array(let urlArray) = pointer.get(from: params) {
            for urlValue in urlArray {
                if case .string(let url) = urlValue {
                    imageUrls.append(url)
                }
            }
        }
        
        // Upload any local file/data URLs to FAL storage to get HTTPS URLs
        var preparedUrls: [String] = []
        for urlString in imageUrls {
            if let uploaded = await uploadIfNeeded(urlString) {
                preparedUrls.append(uploaded)
            } else {
                preparedUrls.append(urlString)
            }
        }

        var dict: [String: Payload] = [
            "prompt": .string(prompt),
            "num_images": .int(numImages),
            "output_format": .string(outputFormat),
            "image_urls": .array(preparedUrls.map { .string($0) })
        ]
        
        return .dict(dict)
    }

    private func buildSeedDreamV4EditInput(from params: JSONValue) async -> Payload {
        // Matches FAL OpenAPI for fal-ai/bytedance/seedream/v4/edit
        // Required: prompt, image_urls[]
        // Optional: image_size{width,height}|preset string, num_images(1..6), max_images(1..6), seed, sync_mode, enable_safety_checker

        let prompt = params.get("/prompt", as: String.self) ?? ""
        let numImages = max(1, min(6, params.get("/num_images", as: Int.self) ?? 1))
        let maxImages = max(1, min(6, params.get("/max_images", as: Int.self) ?? 1))
        let enableSafety = params.get("/enable_safety_checker", as: Bool.self) ?? true
        let seed = params.get("/seed", as: Int.self)

        // image_size may be an object {width,height} or preset string; here we accept object
        let width = params.get("/image_size/width", as: Double.self) ?? 2048
        let height = params.get("/image_size/height", as: Double.self) ?? 2048

        // Extract image_urls array and normalize to HTTPS via uploadIfNeeded
        var rawUrls: [String] = []
        if case .array(let arr) = JSONPointer("/image_urls").get(from: params) {
            for v in arr {
                if case .string(let s) = v { rawUrls.append(s) }
            }
        }
        var preparedUrls: [String] = []
        for url in rawUrls {
            if let uploaded = await uploadIfNeeded(url) {
                preparedUrls.append(uploaded)
            } else {
                preparedUrls.append(url)
            }
        }

        var dict: [String: Payload] = [
            "prompt": .string(prompt),
            "image_size": .dict([
                "width": width.rounded() == width ? .int(Int(width)) : .double(width),
                "height": height.rounded() == height ? .int(Int(height)) : .double(height)
            ]),
            "num_images": .int(numImages),
            "max_images": .int(maxImages),
            "enable_safety_checker": .bool(enableSafety),
            "image_urls": .array(preparedUrls.map { .string($0) })
        ]
        if let seed = seed { dict["seed"] = .int(seed) }
        return .dict(dict)
    }
    
    private func buildFluxInput(from params: JSONValue) -> Payload {
        // Extract supported fields with fallbacks
        let prompt = params.get("/prompt", as: String.self) ?? ""
        let width = params.get("/size/width", as: Double.self) ?? 512
        let height = params.get("/size/height", as: Double.self) ?? 512
        let numImages = params.get("/num_images", as: Int.self) ?? 1
        let seed = params.get("/seed", as: Int.self) ?? Int.random(in: 1..<(Int(Int32.max)))

        var dict: [String: Payload] = [
            "prompt": .string(prompt),
            "image_size": .dict([
                "width": width.rounded() == width ? .int(Int(width)) : .double(width),
                "height": height.rounded() == height ? .int(Int(height)) : .double(height)
            ]),
            "num_images": .int(numImages),
            "seed": .int(seed)
        ]

        // Optional: pass through negative_prompt if present (ignored otherwise)
        if let negative = params.get("/negativePrompt", as: String.self), !negative.isEmpty {
            dict["negative_prompt"] = .string(negative)
        }

        return .dict(dict)
    }
    
    private func buildKlingImageToVideoInput(from params: JSONValue) async -> Payload {
        // Based on FAL OpenAPI for fal-ai/kling-video/v2.5-turbo/pro/image-to-video
        // Required: prompt, image_url; Optional: duration("5"|"10"), cfg_scale(0-1), negative_prompt
        let prompt = params.get("/prompt", as: String.self) ?? ""
        let imageUrl = params.get("/image_url", as: String.self) ?? ""
        let duration = params.get("/duration", as: String.self) ?? "5"
        let cfgScale = params.get("/cfg_scale", as: Double.self) ?? 0.5
        let negative = params.get("/negative_prompt", as: String.self) ?? "blur, distort, and low quality"
        
        // Normalize local references by uploading
        let preparedImageUrl = await uploadIfNeeded(imageUrl) ?? imageUrl

        var dict: [String: Payload] = [
            "prompt": .string(prompt),
            "image_url": .string(preparedImageUrl),
            "duration": .string(duration),
            "cfg_scale": .double(cfgScale),
            "negative_prompt": .string(negative)
        ]
        return .dict(dict)
    }

    private func buildSeedanceImageToVideoInput(from params: JSONValue) async -> Payload {
        // Matches FAL OpenAPI for fal-ai/bytedance/seedance/v1/pro/image-to-video
        // Required: prompt, image_url
        // Optional: duration("3".."12"), aspect_ratio("21:9"|"16:9"|"4:3"|"1:1"|"3:4"|"9:16"|"auto"),
        // resolution("480p"|"720p"|"1080p"), camera_fixed(bool), enable_safety_checker(bool), seed(int), end_image_url(string)

        let prompt = params.get("/prompt", as: String.self) ?? ""
        let duration = params.get("/duration", as: String.self) ?? "5"
        let aspectRatio = params.get("/aspect_ratio", as: String.self) ?? "auto"
        let resolution = params.get("/resolution", as: String.self) ?? "1080p"
        let cameraFixed = params.get("/camera_fixed", as: Bool.self) ?? false
        let enableSafety = params.get("/enable_safety_checker", as: Bool.self) ?? true
        let seed = params.get("/seed", as: Int.self)
        let endImageUrl = params.get("/end_image_url", as: String.self)
        let imageUrl = params.get("/image_url", as: String.self) ?? ""

        let preparedImageUrl = await uploadIfNeeded(imageUrl) ?? imageUrl
        var dict: [String: Payload] = [
            "prompt": .string(prompt),
            "duration": .string(duration),
            "aspect_ratio": .string(aspectRatio),
            "resolution": .string(resolution),
            "camera_fixed": .bool(cameraFixed),
            "enable_safety_checker": .bool(enableSafety),
            "image_url": .string(preparedImageUrl)
        ]
        if let seed = seed { dict["seed"] = .int(seed) }
        if let end = endImageUrl, !end.isEmpty {
            let preparedEndUrl = await uploadIfNeeded(end) ?? end
            dict["end_image_url"] = .string(preparedEndUrl)
        }
        return .dict(dict)
    }

    private func buildWanAnimateMoveInput(from params: JSONValue) async -> Payload {
        // Based on FAL OpenAPI for fal-ai/wan/v2.2-14b/animate/move
        // Required: video_url, image_url
        // Optional: resolution(480p|580p|720p), seed, num_inference_steps(2..40),
        // enable_safety_checker, enable_output_safety_checker, shift(1..10),
        // video_quality(low|medium|high|maximum), video_write_mode(fast|balanced|small)
        let videoUrl = params.get("/video_url", as: String.self) ?? ""
        let imageUrl = params.get("/image_url", as: String.self) ?? ""
        let resolution = params.get("/resolution", as: String.self) ?? "480p"
        let seed = params.get("/seed", as: Int.self)
        let stepsRaw = params.get("/num_inference_steps", as: Int.self) ?? 20
        let steps = max(2, min(40, stepsRaw))
        let enableSafety = params.get("/enable_safety_checker", as: Bool.self) ?? false
        let enableOutputSafety = params.get("/enable_output_safety_checker", as: Bool.self) ?? false
        let shiftRaw = params.get("/shift", as: Double.self) ?? 5.0
        let shift = max(1.0, min(10.0, shiftRaw))
        let videoQuality = params.get("/video_quality", as: String.self) ?? "high"
        let videoWriteMode = params.get("/video_write_mode", as: String.self) ?? "balanced"

        // Upload local file/data references to FAL storage to obtain HTTPS URLs
        let preparedVideoUrl = await uploadIfNeeded(videoUrl) ?? videoUrl
        let preparedImageUrl = await uploadIfNeeded(imageUrl) ?? imageUrl

        var dict: [String: Payload] = [
            "video_url": .string(preparedVideoUrl),
            "image_url": .string(preparedImageUrl),
            "resolution": .string(resolution),
            "num_inference_steps": .int(steps),
            "enable_safety_checker": .bool(enableSafety),
            "enable_output_safety_checker": .bool(enableOutputSafety),
            "shift": .double(shift),
            "video_quality": .string(videoQuality),
            "video_write_mode": .string(videoWriteMode)
        ]
        if let seed = seed { dict["seed"] = .int(seed) }
        return .dict(dict)
    }

    // MARK: - File upload normalization
    // Returns HTTPS URL string if upload was performed, otherwise nil
    private func uploadIfNeeded(_ urlString: String) async -> String? {
        guard !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") { return nil }

        // file:// path
        if urlString.hasPrefix("file://"), let url = URL(string: urlString) {
            do {
                let data = try Data(contentsOf: url)
                let remoteUrl: String = try await fal.storage.upload(data: data)
                return remoteUrl
            } catch {
                print("⚠️ uploadIfNeeded: failed to upload file URL=\(urlString) error=\(error)")
                return nil
            }
        }

        // data: URI
        if urlString.hasPrefix("data:") {
            if let data = decodeDataURI(urlString) {
                do {
                    let remoteUrl: String = try await fal.storage.upload(data: data)
                    return remoteUrl
                } catch {
                    print("⚠️ uploadIfNeeded: failed to upload data URI error=\(error)")
                    return nil
                }
            }
            return nil
        }

        // Unknown scheme; leave as-is
        return nil
    }

    private func decodeDataURI(_ uri: String) -> Data? {
        // Expect format: data:<mime>;base64,<payload>
        guard let commaIndex = uri.firstIndex(of: ",") else { return nil }
        let meta = uri[..<commaIndex]
        guard meta.contains(";base64") else { return nil }
        let b64Start = uri.index(after: commaIndex)
        let b64 = String(uri[b64Start...])
        return Data(base64Encoded: b64)
    }
    
    private func jsonValueToPayload(_ value: JSONValue) -> Payload {
        switch value {
        case .string(let s): return .string(s)
        case .number(let d):
            if d.rounded() == d { return .int(Int(d)) }
            return .double(d)
        case .bool(let b): return .bool(b)
        case .null: return .nilValue
        case .array(let arr): return .array(arr.map { jsonValueToPayload($0) })
        case .object(let dict):
            var map: [String: Payload] = [:]
            for (k, v) in dict { map[k] = jsonValueToPayload(v) }
            return .dict(map)
        }
    }
    
    private func payloadToJSONValue(_ payload: Payload) -> JSONValue? {
        switch payload {
        case .string(let s): return .string(s)
        case .int(let i): return .number(Double(i))
        case .bool(let b): return .bool(b)
        case .double(let d): return .number(d)
        case .date(let d): return .string(ISO8601DateFormatter().string(from: d))
        case .data(let data): return .string("data:application/octet-stream;base64,\(data.base64EncodedString())")
        case .array(let arr): return .array(arr.compactMap { payloadToJSONValue($0) })
        case .dict(let dict):
            var obj: [String: JSONValue] = [:]
            for (k, v) in dict { if let jv = payloadToJSONValue(v) { obj[k] = jv } }
            return .object(obj)
        case .nilValue: return .null
        }
    }
    
    private func extractArtifactsAndOutputs(from result: Payload, originalPrompt: String) async -> ([ArtifactRef], JSONValue?) {
        var refs: [ArtifactRef] = []
        var outputs: JSONValue? = payloadToJSONValue(result)
        
        // Add the original prompt to the outputs if it's not already there or is empty
        if case .object(let outputsDict) = outputs {
            var updatedOutputs = outputsDict
            // Only update if prompt is missing or empty
            if case .string(let existingPrompt) = outputsDict["prompt"], !existingPrompt.isEmpty {
                // Keep the existing prompt from FAL
            } else {
                // Use our original prompt
                updatedOutputs["prompt"] = .string(originalPrompt)
            }
            outputs = .object(updatedOutputs)
        } else {
            // If outputs is nil or not an object, create a new object with the prompt
            outputs = .object(["prompt": .string(originalPrompt)])
        }
        
        // Extract image URLs from the FAL response
        let urls = extractURLStrings(from: result)
        for urlString in urls {
            guard let url = URL(string: urlString) else { continue }
            let mime = guessMimeType(from: url)
            let kind = mime.hasPrefix("video/") ? "video" : (mime.hasPrefix("image/") ? "image" : "binary")
            
            do {
                // Download the media for local preview
                let data = try await download(url: url)
                let localArtifact = try artifactManager.storeArtifact(
                    data: data,
                    kind: kind,
                    mimeType: mime
                )
                
                // Create a hybrid artifact that stores both the local file and original URL
                let artifact = Artifact(
                    kind: kind,
                    mimeType: mime,
                    storage: "hybrid", // Indicates we have both local and remote versions
                    uri: urlString, // Store the FAL URL for API usage
                    contentHash: localArtifact.contentHash,
                    sizePx: localArtifact.sizePx,
                    durationSec: localArtifact.durationSec
                )
                
                // Store the artifact with both local and remote info
                persistence.storeArtifact(artifact)
                
                // Include the original prompt and local file info in metadata
                let metadata: JSONValue = .object([
                    "prompt": .string(originalPrompt),
                    "local_uri": .string(localArtifact.uri),
                    "remote_uri": .string(urlString)
                ])
                
                refs.append(ArtifactRef(
                    kind: kind, 
                    mimeType: mime, 
                    uri: urlString, // Use the FAL URL for API calls
                    sizePx: localArtifact.sizePx, 
                    durationSec: localArtifact.durationSec, 
                    metadata: metadata
                ))
            } catch {
                // If download fails, still store the remote URL for API usage
                print("Failed to download media from \(urlString): \(error)")
                
                let artifact = Artifact(
                    kind: kind,
                    mimeType: mime,
                    storage: "remote",
                    uri: urlString,
                    contentHash: "fal_\(UUID().uuidString)",
                    sizePx: nil,
                    durationSec: nil
                )
                
                persistence.storeArtifact(artifact)
                
                let metadata: JSONValue = .object([
                    "prompt": .string(originalPrompt),
                    "download_failed": .bool(true)
                ])
                
                refs.append(ArtifactRef(
                    kind: kind, 
                    mimeType: mime, 
                    uri: urlString, 
                    sizePx: nil, 
                    durationSec: nil, 
                    metadata: metadata
                ))
            }
        }
        
        return (refs, outputs)
    }
    
    private func extractURLStrings(from payload: Payload) -> [String] {
        var results: [String] = []
        switch payload {
        case .string(let s):
            if s.hasPrefix("http://") || s.hasPrefix("https://") { results.append(s) }
        case .array(let arr):
            for v in arr { results.append(contentsOf: extractURLStrings(from: v)) }
        case .dict(let dict):
            for (_, v) in dict { results.append(contentsOf: extractURLStrings(from: v)) }
        default:
            break
        }
        return results.filter { $0.contains(".png") || $0.contains(".jpg") || $0.contains(".jpeg") || $0.contains(".gif") || $0.contains(".webp") || $0.contains(".mp4") || $0.contains(".mov") || $0.contains(".webm") }
    }
    
    private func guessMimeType(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        default: return "application/octet-stream"
        }
    }
    
    private func download(url: URL) async throws -> Data {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }
}


