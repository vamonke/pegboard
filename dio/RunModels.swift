import Foundation
import CoreGraphics

// MARK: - Run Status

public enum RunStatus: String, Codable, CaseIterable {
    case queued = "queued"
    case running = "running"
    case succeeded = "succeeded"
    case failed = "failed"
    case canceled = "canceled"
    
    public var displayName: String {
        switch self {
        case .queued: return "Queued"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .canceled: return "Canceled"
        }
    }
    
    public var iconName: String {
        switch self {
        case .queued: return "clock"
        case .running: return "play.circle"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .canceled: return "stop.circle"
        }
    }
    
    public var color: String {
        switch self {
        case .queued: return "orange"
        case .running: return "blue"
        case .succeeded: return "green"
        case .failed: return "red"
        case .canceled: return "gray"
        }
    }
    
    public var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .canceled:
            return true
        case .queued, .running:
            return false
        }
    }
    
    public var isActive: Bool {
        switch self {
        case .queued, .running:
            return true
        case .succeeded, .failed, .canceled:
            return false
        }
    }
}

// MARK: - Model Reference

public struct ModelRef: Codable, Equatable {
    public let provider: String       // "FAL", "WaveSpeed", "Mock"
    public let modelID: String        // "sdxl-turbo", "flux-pro-1.1"
    public let endpoint: String       // "/image/generate"
    public let mode: String          // "sync"|"async"
    public let defaultArgs: JSONValue
    
    public init(provider: String, modelID: String, endpoint: String, mode: String = "sync", defaultArgs: JSONValue = .object([:])) {
        self.provider = provider
        self.modelID = modelID
        self.endpoint = endpoint
        self.mode = mode
        self.defaultArgs = defaultArgs
    }
    
    public var displayName: String {
        return "\(provider):\(modelID)"
    }
    
    public var fullEndpoint: String {
        return "\(provider)\(endpoint)"
    }
}

// MARK: - Run Model

public struct Run: Codable, Identifiable, Equatable {
    public let id: UUID
    public let nodeID: UUID
    public let runKey: String          // ULID for idempotency
    public let startedAt: Date
    public var finishedAt: Date?
    public var status: RunStatus       // queued|running|succeeded|failed|canceled
    public let model: ModelRef         // provider:model_id:endpoint
    public let inputParams: JSONValue  // resolved args after bindings
    public let resolvedInputs: JSONValue // values from upstream ports
    public var outputsMeta: JSONValue? // lightweight descriptors
    public var errorCode: String?
    public var errorMessage: String?
    public var billedUSD: Decimal?
    public let nodeSchemaVersion: Int
    public let nodeArgsSnapshot: JSONValue
    public var adapterDebug: JSONValue?
    
    public init(
        id: UUID = UUID(),
        nodeID: UUID,
        runKey: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        status: RunStatus = .queued,
        model: ModelRef,
        inputParams: JSONValue,
        resolvedInputs: JSONValue,
        outputsMeta: JSONValue? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        billedUSD: Decimal? = nil,
        nodeSchemaVersion: Int,
        nodeArgsSnapshot: JSONValue,
        adapterDebug: JSONValue? = nil
    ) {
        self.id = id
        self.nodeID = nodeID
        self.runKey = runKey
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.model = model
        self.inputParams = inputParams
        self.resolvedInputs = resolvedInputs
        self.outputsMeta = outputsMeta
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.billedUSD = billedUSD
        self.nodeSchemaVersion = nodeSchemaVersion
        self.nodeArgsSnapshot = nodeArgsSnapshot
        self.adapterDebug = adapterDebug
    }
    
    // MARK: - Helper Methods
    
    public var duration: TimeInterval? {
        guard let finishedAt = finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
    
    public var isCompleted: Bool {
        return status.isTerminal
    }
    
    public var isActive: Bool {
        return status.isActive
    }
    
    public var hasError: Bool {
        return status == .failed && (errorCode != nil || errorMessage != nil)
    }
    
    public var costDisplay: String {
        guard let billedUSD = billedUSD else { return "Free" }
        return String(format: "$%.4f", billedUSD as NSDecimalNumber)
    }
    
    public var durationDisplay: String {
        guard let duration = duration else { return "Running..." }
        
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Artifact Model

public struct Artifact: Codable, Identifiable {
    public let id: UUID
    public let kind: String            // "image"|"video"|"json"|"text"
    public let mimeType: String
    public let storage: String         // "local"|"remote"
    public let uri: String            // file://, ph://, https://
    public let contentHash: String    // SHA-256
    public let sizePx: CGSize?
    public let durationSec: Float?
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        kind: String,
        mimeType: String,
        storage: String,
        uri: String,
        contentHash: String,
        sizePx: CGSize? = nil,
        durationSec: Float? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.mimeType = mimeType
        self.storage = storage
        self.uri = uri
        self.contentHash = contentHash
        self.sizePx = sizePx
        self.durationSec = durationSec
        self.createdAt = createdAt
    }
    
    // MARK: - Helper Methods
    
    public var isImage: Bool {
        return kind == "image" || mimeType.hasPrefix("image/")
    }
    
    public var isVideo: Bool {
        return kind == "video" || mimeType.hasPrefix("video/")
    }
    
    public var isText: Bool {
        return kind == "text" || mimeType.hasPrefix("text/")
    }
    
    public var isJSON: Bool {
        return kind == "json" || mimeType == "application/json"
    }
    
    public var displayName: String {
        let url = URL(string: uri)
        return url?.lastPathComponent ?? "Unknown"
    }
    
    public var sizeDisplay: String {
        if let sizePx = sizePx {
            return "\(Int(sizePx.width))×\(Int(sizePx.height))"
        }
        return "Unknown size"
    }
    
    public var durationDisplay: String? {
        guard let durationSec = durationSec else { return nil }
        
        if durationSec < 60 {
            return String(format: "%.1fs", durationSec)
        } else {
            let minutes = Int(durationSec / 60)
            let seconds = Int(durationSec.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
    
    public var iconName: String {
        switch kind {
        case "image": return "photo"
        case "video": return "video"
        case "text": return "doc.text"
        case "json": return "curlybraces"
        default: return "doc"
        }
    }
}

// MARK: - Run Artifact Link

public struct RunArtifact: Codable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let artifactID: UUID
    public let role: String           // "primary"|"preview"|"thumb"|"log"
    public let index: Int             // for multi-image/video sets
    
    public init(
        id: UUID = UUID(),
        runID: UUID,
        artifactID: UUID,
        role: String,
        index: Int = 0
    ) {
        self.id = id
        self.runID = runID
        self.artifactID = artifactID
        self.role = role
        self.index = index
    }
    
    // MARK: - Helper Methods
    
    public var isPrimary: Bool {
        return role == "primary"
    }
    
    public var isPreview: Bool {
        return role == "preview"
    }
    
    public var isThumbnail: Bool {
        return role == "thumb"
    }
    
    public var isLog: Bool {
        return role == "log"
    }
}

// MARK: - ULID Generation

public struct ULID {
    private static let chars = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    
    public static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        var result = ""
        
        // Encode timestamp (10 characters)
        var temp = timestamp
        for _ in 0..<10 {
            result = String(chars[chars.index(chars.startIndex, offsetBy: Int(temp % 32))]) + result
            temp /= 32
        }
        
        // Add random part (16 characters)
        for _ in 0..<16 {
            let randomIndex = Int.random(in: 0..<32)
            result += String(chars[chars.index(chars.startIndex, offsetBy: randomIndex)])
        }
        
        return result
    }
}

// MARK: - Content Hashing

import CryptoKit

public struct ContentHasher {
    public static func hash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    public static func hash(fileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return hash(data: data)
    }
    
    public static func hash(string: String) -> String {
        let data = string.data(using: .utf8) ?? Data()
        return hash(data: data)
    }
}
