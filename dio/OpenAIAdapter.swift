import Foundation
import ImageIO
import CoreGraphics

// MARK: - OpenAI Adapter (Sora video only)

public class OpenAIAdapter: CloudAdapter {
    public let provider = "OpenAI"
    public var isAvailable: Bool { apiKey != nil }
    
    private let artifactManager = ArtifactManager.shared
    private let persistence = RunPersistence.shared
    private let apiBase = URL(string: "https://api.openai.com/v1")!
    private let urlSession: URLSession
    
    private var apiKey: String? {
        // Prefer environment variable, fallback to Info.plist
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return key
        }
        if let infoDict = Bundle.main.infoDictionary, let key = infoDict["OPENAI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return nil
    }
    
    public init(session: URLSession = .shared) {
        self.urlSession = session
    }
    
    // MARK: - CloudAdapter
    
    public func invoke(_ request: InvocationRequest) async throws -> InvocationResponse {
        // Only support video creation through Sora models
        let modelID = request.model.modelID.isEmpty ? "sora-2" : request.model.modelID
        let prompt = request.params.get("/prompt", as: String.self) ?? ""
        let sizeString: String = {
            // Use JSON Pointer style paths with leading slash
            let w = request.params.get("/size/width", as: Double.self) ?? 1280
            let h = request.params.get("/size/height", as: Double.self) ?? 720
            return "\(Int(w))x\(Int(h))"
        }()
        let durationSeconds = request.params.get("/seconds", as: Double.self) ?? request.params.get("/duration", as: Double.self) ?? 4.0
        
        do {
            let create = try await createVideo(model: modelID, prompt: prompt, size: sizeString, seconds: durationSeconds, params: request.params)
            // If completed immediately, continue to download; else poll.
            if let status = create["status"] as? String, status == "completed", let id = create["id"] as? String {
                return try await finalizeAndRespond(videoID: id, originalPrompt: prompt)
            }
            guard let jobID = create["id"] as? String else {
                return InvocationResponse(status: "failed", errorCode: "OPENAI_CREATE_NO_ID", errorMessage: "Missing job id", vendorMeta: jsonToJSONValue(create))
            }
            // Return queued and let engine poll using poll()
            return InvocationResponse(status: "queued", outputs: jsonToJSONValue(create), artifacts: nil, errorCode: nil, errorMessage: nil, billedUSD: nil, vendorMeta: jsonToJSONValue(create), jobID: jobID)
        } catch {
            return InvocationResponse(status: "failed", errorCode: "OPENAI_CREATE_ERROR", errorMessage: error.localizedDescription)
        }
    }
    
    public func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse {
        do {
            let status = try await retrieveVideo(videoID: jobID)
            let state = (status["status"] as? String) ?? "in_progress"
            let progress = (status["progress"] as? Double) ?? ((status["progress"] as? NSNumber)?.doubleValue)
            if let p = progress {
                print(String(format: "[OpenAIAdapter] Poll status=%@ progress=%.1f%% id=%@", state, p, jobID))
            } else {
                print("[OpenAIAdapter] Poll status=\(state) id=\(jobID)")
            }
            if state == "completed" {
                return try await finalizeAndRespond(videoID: jobID, originalPrompt: (status["prompt"] as? String) ?? "")
            } else if state == "failed" {
                let errMsg = (status["error"] as? [String: Any])?["message"] as? String
                return InvocationResponse(status: "failed", errorCode: "OPENAI_JOB_FAILED", errorMessage: errMsg, vendorMeta: jsonToJSONValue(status))
            } else if state == "cancelled" || state == "canceled" {
                return InvocationResponse(status: "cancelled", vendorMeta: jsonToJSONValue(status))
            } else {
                return InvocationResponse(status: state == "queued" ? "queued" : "running", outputs: jsonToJSONValue(status), vendorMeta: jsonToJSONValue(status), jobID: jobID)
            }
        } catch {
            let nsErr = error as NSError
            print("[OpenAIAdapter] Poll error domain=\(nsErr.domain) code=\(nsErr.code) desc=\(nsErr.localizedDescription)")
            return InvocationResponse(status: "failed", errorCode: "OPENAI_POLL_ERROR", errorMessage: error.localizedDescription)
        }
    }
    
    public func cancel(jobID: String, credentialID: UUID) async throws -> Bool {
        // OpenAI Videos API does not document cancellation for a specific job at time of writing.
        return false
    }
    
    // MARK: - API Calls
    
    private func createVideo(model: String, prompt: String, size: String, seconds: Double, params: JSONValue) async throws -> [String: Any] {
        guard let apiKey = apiKey else { throw AdapterError.invalidCredentials }
        let url = apiBase.appendingPathComponent("videos")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // multipart/form-data if input_reference present; otherwise JSON is acceptable per docs snippets,
        // but we'll always use multipart for flexibility.
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        appendField("model", model)
        appendField("prompt", prompt)
        // append size later after potentially reconciling with input_reference dimensions
        // append seconds early (doesn't depend on reference)
        appendField("seconds", String(Int(seconds)))
        
        // Optional: input_reference (image first frame) as file if path/URL provided in params at /input_reference
        // Debug: print requested size and input image dimensions (if available)
        var finalSizeString = size
        var inputRefWidth: Int?
        var inputRefHeight: Int?
        do {
            let reqW = Int(params.get("/size/width", as: Double.self) ?? 1280)
            let reqH = Int(params.get("/size/height", as: Double.self) ?? 720)
            print("[OpenAIAdapter] Requested video size: \(reqW)x\(reqH) (size=\(size))")
        }
        if let ref = params.get("/input_reference", as: String.self), !ref.isEmpty {
            if let url = URL(string: ref), let data = try? Data(contentsOf: url) {
                // Attempt to read pixel dimensions of the input image
                if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                   let props = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                   let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
                   let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
                    print("[OpenAIAdapter] input_reference: \(url.absoluteString)")
                    print("[OpenAIAdapter] input_reference dimensions: \(Int(w))x\(Int(h)) pixels")
                    inputRefWidth = Int(w)
                    inputRefHeight = Int(h)
                } else {
                    print("[OpenAIAdapter] input_reference: \(url.absoluteString) (could not determine pixel size)")
                }
                let mime = guessMimeType(from: url)
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"input_reference\"; filename=\"reference\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
                body.append(data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }
        // Reconcile size with input_reference if needed
        if let w = inputRefWidth, let h = inputRefHeight {
            let requestedW = Int(params.get("/size/width", as: Double.self) ?? 1280)
            let requestedH = Int(params.get("/size/height", as: Double.self) ?? 720)
            if requestedW != w || requestedH != h {
                print("[OpenAIAdapter] Adjusting requested size to match input_reference: \(w)x\(h)")
                finalSizeString = "\(w)x\(h)"
            }
        }
        appendField("size", finalSizeString)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await urlSession.data(for: request)
        try ensureSuccess(response: response, data: data)
        return try decodeJSONDictionary(data)
    }
    
    private func retrieveVideo(videoID: String) async throws -> [String: Any] {
        guard let apiKey = apiKey else { throw AdapterError.invalidCredentials }
        let url = apiBase.appendingPathComponent("videos/\(videoID)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: req)
        try ensureSuccess(response: response, data: data)
        return try decodeJSONDictionary(data)
    }
    
    private func downloadContent(videoID: String, variant: String = "video") async throws -> Data {
        guard let apiKey = apiKey else { throw AdapterError.invalidCredentials }
        let url = apiBase.appendingPathComponent("videos/\(videoID)/content\(variant == "video" ? "" : "?variant=\(variant)")")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await urlSession.data(for: req)
        try ensureSuccess(response: response, data: data)
        return data
    }
    
    // MARK: - Finalization
    
    private func finalizeAndRespond(videoID: String, originalPrompt: String) async throws -> InvocationResponse {
        // Download primary MP4
        let videoData = try await downloadContent(videoID: videoID, variant: "video")
        let artifact = try artifactManager.storeArtifact(
            data: videoData,
            kind: "video",
            mimeType: "video/mp4",
            durationSec: nil
        )
        // Persist the artifact record for linking
        persistence.storeArtifact(artifact)
        
        let ref = ArtifactRef(
            kind: "video",
            mimeType: "video/mp4",
            uri: artifact.uri,
            durationSec: nil,
            metadata: .object([
                "prompt": .string(originalPrompt),
                "provider_uri": .string("openai://videos/\(videoID)")
            ])
        )
        
        // Outputs metadata similar to other adapters
        let outputs: JSONValue = .object([
            "video_id": .string(videoID),
            "prompt": .string(originalPrompt)
        ])
        
        return InvocationResponse(
            status: "succeeded",
            outputs: outputs,
            artifacts: [ref],
            billedUSD: nil,
            vendorMeta: .object([
                "provider": .string("OpenAI"),
                "video_id": .string(videoID)
            ])
        )
    }
    
    // MARK: - Utilities
    
    private func decodeJSONDictionary(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = object as? [String: Any] else {
            throw AdapterError.invalidRequest("Invalid response format")
        }
        return dict
    }
    
    private func ensureSuccess(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[OpenAIAdapter] HTTP error status=\(http.statusCode) body=\(body)")
            throw AdapterError.invalidRequest("HTTP \(http.statusCode): \(body)")
        }
    }
    
    private func jsonToJSONValue(_ dict: [String: Any]) -> JSONValue {
        // Best-effort conversion for debug/vendorMeta
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return json
        }
        return .null
    }
    
    private func guessMimeType(from url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }
}


