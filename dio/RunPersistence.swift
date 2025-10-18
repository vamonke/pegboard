import Foundation
import Combine

// MARK: - Run Persistence Manager

public class RunPersistence: ObservableObject {
    public static let shared = RunPersistence()
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let runsFile: URL
    private let artifactsFile: URL
    private let runArtifactsFile: URL
    
    // In-memory storage for fast access
    @Published public private(set) var runs: [UUID: Run] = [:]
    @Published public private(set) var artifacts: [UUID: Artifact] = [:]
    @Published public private(set) var runArtifacts: [UUID: RunArtifact] = [:]
    
    // MARK: - Initialization
    
    private init() {
        // Create base directory in Documents/Runs
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDirectory = documentsPath.appendingPathComponent("Runs")
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        
        // Define file paths
        runsFile = baseDirectory.appendingPathComponent("runs.json")
        artifactsFile = baseDirectory.appendingPathComponent("artifacts.json")
        runArtifactsFile = baseDirectory.appendingPathComponent("run_artifacts.json")
        
        // Load existing data
        loadAllData()
    }
    
    // MARK: - Data Loading
    
    private func loadAllData() {
        loadRuns()
        loadArtifacts()
        loadRunArtifacts()
    }
    
    private func loadRuns() {
        guard fileManager.fileExists(atPath: runsFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: runsFile)
            let decoder = JSONDecoder()
            let runsArray = try decoder.decode([Run].self, from: data)
            
            runs = Dictionary(uniqueKeysWithValues: runsArray.map { ($0.id, $0) })
        } catch {
            print("Failed to load runs: \(error)")
        }
    }
    
    private func loadArtifacts() {
        guard fileManager.fileExists(atPath: artifactsFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: artifactsFile)
            let decoder = JSONDecoder()
            let artifactsArray = try decoder.decode([Artifact].self, from: data)
            
            artifacts = Dictionary(uniqueKeysWithValues: artifactsArray.map { ($0.id, $0) })
        } catch {
            print("Failed to load artifacts: \(error)")
        }
    }
    
    private func loadRunArtifacts() {
        guard fileManager.fileExists(atPath: runArtifactsFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: runArtifactsFile)
            let decoder = JSONDecoder()
            let runArtifactsArray = try decoder.decode([RunArtifact].self, from: data)
            
            runArtifacts = Dictionary(uniqueKeysWithValues: runArtifactsArray.map { ($0.id, $0) })
        } catch {
            print("Failed to load run artifacts: \(error)")
        }
    }
    
    // MARK: - Data Saving
    
    private func saveRuns() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(runs.values))
            try data.write(to: runsFile)
        } catch {
            print("Failed to save runs: \(error)")
        }
    }
    
    private func saveArtifacts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(Array(artifacts.values))
            try data.write(to: artifactsFile)
        } catch {
            print("Failed to save artifacts: \(error)")
        }
    }
    
    private func saveRunArtifacts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(Array(runArtifacts.values))
            try data.write(to: runArtifactsFile)
        } catch {
            print("Failed to save run artifacts: \(error)")
        }
    }
    
    // MARK: - Run Management
    
    public func createRun(
        nodeID: UUID,
        model: ModelRef,
        inputParams: JSONValue,
        resolvedInputs: JSONValue,
        nodeSchemaVersion: Int,
        nodeArgsSnapshot: JSONValue
    ) -> Run {
        let run = Run(
            nodeID: nodeID,
            runKey: ULID.generate(),
            model: model,
            inputParams: inputParams,
            resolvedInputs: resolvedInputs,
            nodeSchemaVersion: nodeSchemaVersion,
            nodeArgsSnapshot: nodeArgsSnapshot
        )
        
        Task { @MainActor in
            runs[run.id] = run
        }
        saveRuns()
        
        return run
    }
    
    public func updateRun(_ run: Run) {
        Task { @MainActor in
            runs[run.id] = run
        }
        saveRuns()
    }
    
    public func getRun(_ id: UUID) -> Run? {
        return runs[id]
    }
    
    public func getRunsForNode(_ nodeID: UUID) -> [Run] {
        return runs.values.filter { $0.nodeID == nodeID }.sorted { $0.startedAt > $1.startedAt }
    }
    
    public func getActiveRuns() -> [Run] {
        return runs.values.filter { $0.isActive }.sorted { $0.startedAt < $1.startedAt }
    }
    
    public func getRecentRuns(limit: Int = 50) -> [Run] {
        return Array(runs.values.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }
    
    public func deleteRun(_ id: UUID) {
        Task { @MainActor in
            runs.removeValue(forKey: id)
            
            // Also remove associated run artifacts
            let associatedRunArtifacts = runArtifacts.values.filter { $0.runID == id }
            for runArtifact in associatedRunArtifacts {
                runArtifacts.removeValue(forKey: runArtifact.id)
            }
        }
        saveRuns()
        saveRunArtifacts()
    }
    
    // MARK: - Artifact Management
    
    public func storeArtifact(_ artifact: Artifact) {
        Task { @MainActor in
            artifacts[artifact.id] = artifact
        }
        saveArtifacts()
    }
    
    public func getArtifact(_ id: UUID) -> Artifact? {
        return artifacts[id]
    }
    
    public func getAllArtifacts() -> [Artifact] {
        return Array(artifacts.values)
    }
    
    public func getArtifactsForRun(_ runID: UUID) -> [Artifact] {
        let runArtifactLinks = runArtifacts.values.filter { $0.runID == runID }
        print("🔍 RunPersistence - Found \(runArtifactLinks.count) run-artifact links for run \(runID)")
        let result = runArtifactLinks.compactMap { link in
            let artifact = artifacts[link.artifactID]
            print("🔍 RunPersistence - Link: \(link.id), Artifact: \(artifact?.displayName ?? "nil")")
            return artifact
        }
        print("🔍 RunPersistence - Returning \(result.count) artifacts for run \(runID)")
        return result
    }
    
    public func getPrimaryArtifactForRun(_ runID: UUID) -> Artifact? {
        let primaryLink = runArtifacts.values.first { $0.runID == runID && $0.isPrimary }
        print("🔍 RunPersistence - Primary link for run \(runID): \(primaryLink?.id.uuidString ?? "nil")")
        let result = primaryLink.flatMap { artifacts[$0.artifactID] }
        print("🔍 RunPersistence - Primary artifact for run \(runID): \(result?.displayName ?? "nil")")
        return result
    }
    
    public func deleteArtifact(_ id: UUID) {
        Task { @MainActor in
            artifacts.removeValue(forKey: id)
            
            // Also remove associated run artifacts
            let associatedRunArtifacts = runArtifacts.values.filter { $0.artifactID == id }
            for runArtifact in associatedRunArtifacts {
                runArtifacts.removeValue(forKey: runArtifact.id)
            }
        }
        saveArtifacts()
        saveRunArtifacts()
    }
    
    // MARK: - Run Artifact Management
    
    public func linkRunToArtifact(runID: UUID, artifactID: UUID, role: String = "primary", index: Int = 0) {
        let runArtifact = RunArtifact(
            runID: runID,
            artifactID: artifactID,
            role: role,
            index: index
        )
        
        Task { @MainActor in
            runArtifacts[runArtifact.id] = runArtifact
        }
        saveRunArtifacts()
    }
    
    public func unlinkRunFromArtifact(runID: UUID, artifactID: UUID) {
        let linkToRemove = runArtifacts.values.first { $0.runID == runID && $0.artifactID == artifactID }
        if let link = linkToRemove {
            Task { @MainActor in
                runArtifacts.removeValue(forKey: link.id)
            }
            saveRunArtifacts()
        }
    }
    
    public func getRunArtifactsForRun(_ runID: UUID) -> [RunArtifact] {
        return runArtifacts.values.filter { $0.runID == runID }.sorted { $0.index < $1.index }
    }
    
    // MARK: - Statistics and Analytics
    
    public func getRunStatistics() -> RunStatistics {
        let allRuns = Array(runs.values)
        let completedRuns = allRuns.filter { $0.isCompleted }
        
        let statusCounts = Dictionary(grouping: allRuns, by: { $0.status })
            .mapValues { $0.count }
        
        let totalCost = allRuns.compactMap { $0.billedUSD }.reduce(0, +)
        let averageDuration = completedRuns.compactMap { $0.duration }.reduce(0, +) / Double(max(completedRuns.count, 1))
        
        let nodeCounts = Dictionary(grouping: allRuns, by: { $0.nodeID })
            .mapValues { $0.count }
        
        return RunStatistics(
            totalRuns: allRuns.count,
            completedRuns: completedRuns.count,
            activeRuns: allRuns.filter { $0.isActive }.count,
            statusCounts: statusCounts,
            totalCost: totalCost,
            averageDuration: averageDuration,
            nodeRunCounts: nodeCounts,
            lastRunAt: allRuns.map { $0.startedAt }.max()
        )
    }
    
    public func getArtifactStatistics() -> ArtifactStatistics {
        let allArtifacts = Array(artifacts.values)
        
        let kindCounts = Dictionary(grouping: allArtifacts, by: { $0.kind })
            .mapValues { $0.count }
        
        let totalSize = allArtifacts.compactMap { artifact in
            guard let url = URL(string: artifact.uri) else { return nil }
            return try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
        }.reduce(0, +)
        
        return ArtifactStatistics(
            totalArtifacts: allArtifacts.count,
            kindCounts: kindCounts,
            totalSize: totalSize,
            lastArtifactAt: allArtifacts.map { $0.createdAt }.max()
        )
    }
    
    // MARK: - Cleanup and Maintenance
    
    public func cleanupOldRuns(olderThan days: Int = 30) {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(days * 24 * 60 * 60))
        let oldRuns = runs.values.filter { $0.startedAt < cutoffDate }
        
        Task { @MainActor in
            for run in oldRuns {
                runs.removeValue(forKey: run.id)
                
                // Also remove associated run artifacts
                let associatedRunArtifacts = runArtifacts.values.filter { $0.runID == run.id }
                for runArtifact in associatedRunArtifacts {
                    runArtifacts.removeValue(forKey: runArtifact.id)
                }
            }
        }
        
        saveRuns()
        saveRunArtifacts()
    }
    
    public func exportData() -> Data? {
        let exportData = ExportData(
            runs: Array(runs.values),
            artifacts: Array(artifacts.values),
            runArtifacts: Array(runArtifacts.values),
            exportedAt: Date()
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(exportData)
        } catch {
            print("Failed to export data: \(error)")
            return nil
        }
    }
    
    public func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exportData = try decoder.decode(ExportData.self, from: data)
        
        // Merge imported data with existing data
        Task { @MainActor in
            for run in exportData.runs {
                runs[run.id] = run
            }
            
            for artifact in exportData.artifacts {
                artifacts[artifact.id] = artifact
            }
            
            for runArtifact in exportData.runArtifacts {
                runArtifacts[runArtifact.id] = runArtifact
            }
        }
        
        // Save all data
        saveRuns()
        saveArtifacts()
        saveRunArtifacts()
    }
}

// MARK: - Statistics Models

public struct RunStatistics {
    public let totalRuns: Int
    public let completedRuns: Int
    public let activeRuns: Int
    public let statusCounts: [RunStatus: Int]
    public let totalCost: Decimal
    public let averageDuration: TimeInterval
    public let nodeRunCounts: [UUID: Int]
    public let lastRunAt: Date?
    
    public var successRate: Double {
        guard completedRuns > 0 else { return 0 }
        let successfulRuns = statusCounts[.succeeded] ?? 0
        return Double(successfulRuns) / Double(completedRuns)
    }
    
    public var totalCostDisplay: String {
        return String(format: "$%.4f", totalCost as NSDecimalNumber)
    }
    
    public var averageDurationDisplay: String {
        if averageDuration < 1 {
            return String(format: "%.0fms", averageDuration * 1000)
        } else if averageDuration < 60 {
            return String(format: "%.1fs", averageDuration)
        } else {
            let minutes = Int(averageDuration / 60)
            let seconds = Int(averageDuration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

public struct ArtifactStatistics {
    public let totalArtifacts: Int
    public let kindCounts: [String: Int]
    public let totalSize: Int64
    public let lastArtifactAt: Date?
    
    public var totalSizeDisplay: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// MARK: - Export/Import Models

private struct ExportData: Codable {
    let runs: [Run]
    let artifacts: [Artifact]
    let runArtifacts: [RunArtifact]
    let exportedAt: Date
}
