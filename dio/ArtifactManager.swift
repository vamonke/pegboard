import Foundation
import CryptoKit
import UniformTypeIdentifiers
import ImageIO

// MARK: - Artifact Storage Manager

public class ArtifactManager: ObservableObject {
    public static let shared = ArtifactManager()
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    // MARK: - Initialization
    
    private init() {
        // Create base directory in Documents/Artifacts
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDirectory = documentsPath.appendingPathComponent("Artifacts")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Directory Structure
    
    private func directoryForKind(_ kind: String) -> URL {
        return baseDirectory.appendingPathComponent(kind)
    }
    
    private func urlForArtifact(_ artifact: Artifact) -> URL {
        let kindDirectory = directoryForKind(artifact.kind)
        let fileName = "\(artifact.id.uuidString).\(fileExtension(for: artifact.mimeType))"
        return kindDirectory.appendingPathComponent(fileName)
    }
    
    private func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "video/webm": return "webm"
        case "application/json": return "json"
        case "text/plain": return "txt"
        case "text/markdown": return "md"
        default:
            // Try to get extension from UTType
            if let utType = UTType(mimeType: mimeType) {
                return utType.preferredFilenameExtension ?? "bin"
            }
            return "bin"
        }
    }
    
    // MARK: - Artifact Storage
    
    public func storeArtifact(data: Data, kind: String, mimeType: String, sizePx: CGSize? = nil, durationSec: Float? = nil) throws -> Artifact {
        // Generate content hash
        let contentHash = ContentHasher.hash(data: data)
        
        // Check if artifact already exists
        if let existingArtifact = findArtifactByHash(contentHash) {
            return existingArtifact
        }
        
        // Create artifact record
        let artifact = Artifact(
            kind: kind,
            mimeType: mimeType,
            storage: "local",
            uri: "", // Will be set after file is saved
            contentHash: contentHash,
            sizePx: sizePx,
            durationSec: durationSec
        )
        
        // Create kind directory if needed
        let kindDirectory = directoryForKind(kind)
        try fileManager.createDirectory(at: kindDirectory, withIntermediateDirectories: true)
        
        // Save file
        let fileURL = urlForArtifact(artifact)
        try data.write(to: fileURL)
        
        // Update artifact with file URI
        let updatedArtifact = Artifact(
            id: artifact.id,
            kind: artifact.kind,
            mimeType: artifact.mimeType,
            storage: artifact.storage,
            uri: fileURL.absoluteString,
            contentHash: artifact.contentHash,
            sizePx: artifact.sizePx,
            durationSec: artifact.durationSec,
            createdAt: artifact.createdAt
        )
        
        return updatedArtifact
    }
    
    public func storeArtifact(from url: URL, kind: String, mimeType: String, sizePx: CGSize? = nil, durationSec: Float? = nil) throws -> Artifact {
        let data = try Data(contentsOf: url)
        return try storeArtifact(data: data, kind: kind, mimeType: mimeType, sizePx: sizePx, durationSec: durationSec)
    }
    
    public func storeTextArtifact(_ text: String, fileName: String? = nil) throws -> Artifact {
        let data = text.data(using: .utf8) ?? Data()
        return try storeArtifact(data: data, kind: "text", mimeType: "text/plain")
    }
    
    public func storeJSONArtifact(_ json: JSONValue, fileName: String? = nil) throws -> Artifact {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(json)
        return try storeArtifact(data: data, kind: "json", mimeType: "application/json")
    }
    
    // MARK: - Artifact Retrieval
    
    public func loadArtifactData(_ artifact: Artifact) throws -> Data {
        guard artifact.storage == "local" else {
            throw ArtifactError.unsupportedStorage(artifact.storage)
        }
        
        guard let url = URL(string: artifact.uri) else {
            throw ArtifactError.invalidURI(artifact.uri)
        }
        
        return try Data(contentsOf: url)
    }
    
    public func loadTextArtifact(_ artifact: Artifact) throws -> String {
        let data = try loadArtifactData(artifact)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ArtifactError.invalidTextEncoding
        }
        return text
    }
    
    public func loadJSONArtifact(_ artifact: Artifact) throws -> JSONValue {
        let data = try loadArtifactData(artifact)
        let decoder = JSONDecoder()
        return try decoder.decode(JSONValue.self, from: data)
    }
    
    public func getArtifactURL(_ artifact: Artifact) -> URL? {
        // Handle different storage types
        switch artifact.storage {
        case "local":
            return URL(string: artifact.uri)
        case "hybrid":
            // For hybrid storage, prefer local URI if available, fallback to remote
            // The local URI should be in the metadata, but for now we'll try to parse the remote URI
            // TODO: Extract local_uri from metadata when available
            return URL(string: artifact.uri)
        case "remote", "url":
            // For remote URLs, return the URL directly
            return URL(string: artifact.uri)
        default:
            // For any other storage type, try to parse as URL
            return URL(string: artifact.uri)
        }
    }
    
    // MARK: - Artifact Management
    
    public func deleteArtifact(_ artifact: Artifact) throws {
        guard artifact.storage == "local" else {
            throw ArtifactError.unsupportedStorage(artifact.storage)
        }
        
        guard let url = URL(string: artifact.uri) else {
            throw ArtifactError.invalidURI(artifact.uri)
        }
        
        try fileManager.removeItem(at: url)
    }
    
    // Enumerate all artifacts present on local storage under the base Artifacts directory
    public func listAllArtifacts() -> [Artifact] {
        var results: [Artifact] = []
        let kinds = ["image", "video", "text", "json"]
        
        for kind in kinds {
            let kindDirectory = directoryForKind(kind)
            guard fileManager.fileExists(atPath: kindDirectory.path) else { continue }
            
            do {
                let files = try fileManager.contentsOfDirectory(at: kindDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
                for fileURL in files {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let hash = ContentHasher.hash(data: data)
                        let mime = mimeTypeForFile(fileURL)
                        let sizePx = kind == "image" ? getImageSize(for: fileURL) : nil
                        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
                        let createdAt = (attrs[.creationDate] as? Date) ?? Date()
                        
                        let artifact = Artifact(
                            kind: kind,
                            mimeType: mime,
                            storage: "local",
                            uri: fileURL.absoluteString,
                            contentHash: hash,
                            sizePx: sizePx,
                            durationSec: nil,
                            createdAt: createdAt
                        )
                        results.append(artifact)
                    } catch {
                        continue
                    }
                }
            } catch {
                continue
            }
        }
        
        return results
    }

    public func findArtifactByHash(_ hash: String) -> Artifact? {
        // This would typically query a database or index
        // For now, we'll scan the directory structure
        return scanForArtifactByHash(hash)
    }
    
    private func scanForArtifactByHash(_ hash: String) -> Artifact? {
        // Scan all kind directories for files
        let kinds = ["image", "video", "text", "json"]
        
        for kind in kinds {
            let kindDirectory = directoryForKind(kind)
            guard fileManager.fileExists(atPath: kindDirectory.path) else { continue }
            
            do {
                let files = try fileManager.contentsOfDirectory(at: kindDirectory, includingPropertiesForKeys: nil)
                
                for fileURL in files {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let fileHash = ContentHasher.hash(data: data)
                        
                        if fileHash == hash {
                            // Reconstruct artifact from file
                            let mimeType = mimeTypeForFile(fileURL)
                            let sizePx = getImageSize(for: fileURL) // Only for images
                            
                            return Artifact(
                                kind: kind,
                                mimeType: mimeType,
                                storage: "local",
                                uri: fileURL.absoluteString,
                                contentHash: hash,
                                sizePx: sizePx,
                                durationSec: nil
                            )
                        }
                    } catch {
                        // Skip files that can't be read
                        continue
                    }
                }
            } catch {
                // Skip directories that can't be read
                continue
            }
        }
        
        return nil
    }
    
    // MARK: - Utility Methods
    
    public func getStorageInfo() -> StorageInfo {
        var totalSize: Int64 = 0
        var fileCount = 0
        var kindCounts: [String: Int] = [:]
        
        let kinds = ["image", "video", "text", "json"]
        
        for kind in kinds {
            let kindDirectory = directoryForKind(kind)
            guard fileManager.fileExists(atPath: kindDirectory.path) else { continue }
            
            do {
                let files = try fileManager.contentsOfDirectory(at: kindDirectory, includingPropertiesForKeys: [.fileSizeKey])
                kindCounts[kind] = files.count
                fileCount += files.count
                
                for fileURL in files {
                    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let size = attributes[.size] as? Int64 {
                        totalSize += size
                    }
                }
            } catch {
                // Skip directories that can't be read
                continue
            }
        }
        
        return StorageInfo(
            totalSize: totalSize,
            fileCount: fileCount,
            kindCounts: kindCounts
        )
    }
    
    public func cleanupOrphanedFiles() throws {
        // This would typically be called periodically to clean up files
        // that are no longer referenced by any artifacts
        // Implementation would depend on your persistence layer
    }
    
    // MARK: - Helper Methods
    
    private func mimeTypeForFile(_ url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        
        switch pathExtension {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webm": return "video/webm"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "md": return "text/markdown"
        default: return "application/octet-stream"
        }
    }
    
    private func getImageSize(for url: URL) -> CGSize? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = imageProperties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = imageProperties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        
        return CGSize(width: width, height: height)
    }
}

// MARK: - Storage Info

public struct StorageInfo {
    public let totalSize: Int64
    public let fileCount: Int
    public let kindCounts: [String: Int]
    
    public var totalSizeDisplay: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    public var isEmpty: Bool {
        return fileCount == 0
    }
}

// MARK: - Artifact Errors

public enum ArtifactError: Error, LocalizedError {
    case unsupportedStorage(String)
    case invalidURI(String)
    case invalidTextEncoding
    case fileNotFound
    case permissionDenied
    
    public var errorDescription: String? {
        switch self {
        case .unsupportedStorage(let storage):
            return "Unsupported storage type: \(storage)"
        case .invalidURI(let uri):
            return "Invalid artifact URI: \(uri)"
        case .invalidTextEncoding:
            return "Invalid text encoding"
        case .fileNotFound:
            return "Artifact file not found"
        case .permissionDenied:
            return "Permission denied accessing artifact"
        }
    }
}
