import Foundation
import SwiftUI
import Combine

// MARK: - Mock Adapter Demo

struct MockAdapterDemo: View {
    @StateObject private var adapterRegistry = AdapterRegistry.shared
    @StateObject private var persistence = RunPersistence.shared
    @State private var selectedAdapter: CloudAdapter?
    @State private var testResults: [AdapterTestResult] = []
    @State private var isRunningTest = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mock Adapter System Demo")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Test the cloud adapter system with mock providers")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                // Available Adapters
                VStack(alignment: .leading, spacing: 10) {
                    Text("Available Adapters")
                        .font(.headline)
                    
                    ForEach(adapterRegistry.getAvailableAdapters(), id: \.provider) { adapter in
                        AdapterCard(adapter: adapter, isSelected: selectedAdapter?.provider == adapter.provider) {
                            selectedAdapter = adapter
                        }
                    }
                }
                
                Divider()
                
                // Test Controls
                if let adapter = selectedAdapter {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Test Controls")
                            .font(.headline)
                        
                        HStack(spacing: 10) {
                            Button("Test Image Generation") {
                                runTest(adapter: adapter, testType: .image)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRunningTest)
                            
                            Button("Test Video Generation") {
                                runTest(adapter: adapter, testType: .video)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunningTest)
                            
                            Button("Test Async Operation") {
                                runTest(adapter: adapter, testType: .async)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunningTest)
                        }
                        
                        if isRunningTest {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Running test...")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Test Results
                if !testResults.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Test Results")
                            .font(.headline)
                        
                        ForEach(testResults.prefix(10), id: \.id) { result in
                            TestResultRowView(result: result)
                        }
                    }
                }
                
                Divider()
                
                // Recent Runs
                let recentRuns = persistence.getRecentRuns(limit: 10)
                if !recentRuns.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recent Runs")
                            .font(.headline)
                        
                        ForEach(recentRuns.prefix(5), id: \.id) { run in
                            RunRowView(run: run)
                        }
                    }
                }
                
                Spacer()
            }
        }
        .padding()
        .onAppear {
            selectedAdapter = adapterRegistry.getAvailableAdapters().first
        }
    }
    
    // MARK: - Test Methods
    
    private func runTest(adapter: CloudAdapter, testType: TestType) {
        isRunningTest = true
        
        Task {
            let result = await performTest(adapter: adapter, testType: testType)
            
            await MainActor.run {
                testResults.insert(result, at: 0)
                isRunningTest = false
            }
        }
    }
    
    private func performTest(adapter: CloudAdapter, testType: TestType) async -> AdapterTestResult {
        let startTime = Date()
        
        do {
            let request = createTestRequest(for: testType)
            let response = try await adapter.invoke(request)
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            return AdapterTestResult(
                id: UUID(),
                adapter: adapter.provider,
                testType: testType,
                status: response.status,
                duration: duration,
                billedUSD: response.billedUSD,
                errorMessage: response.errorMessage,
                artifactCount: response.artifacts?.count ?? 0,
                timestamp: startTime
            )
        } catch {
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            return AdapterTestResult(
                id: UUID(),
                adapter: adapter.provider,
                testType: testType,
                status: "failed",
                duration: duration,
                billedUSD: nil,
                errorMessage: error.localizedDescription,
                artifactCount: 0,
                timestamp: startTime
            )
        }
    }
    
    private func createTestRequest(for testType: TestType) -> InvocationRequest {
        switch testType {
        case .image:
            return InvocationRequest(
                model: ModelRef(
                    provider: "Mock",
                    modelID: "image-generator",
                    endpoint: "/image/generate"
                ),
                params: .object([
                    "prompt": .string("A beautiful sunset over mountains"),
                    "size": .object([
                        "width": .number(512),
                        "height": .number(512)
                    ])
                ]),
                runKey: ULID.generate(),
                credentialID: UUID()
            )
            
        case .video:
            return InvocationRequest(
                model: ModelRef(
                    provider: "Mock",
                    modelID: "video-generator",
                    endpoint: "/video/generate"
                ),
                params: .object([
                    "prompt": .string("A time-lapse of clouds moving across the sky"),
                    "duration": .number(5.0),
                ]),
                runKey: ULID.generate(),
                credentialID: UUID()
            )
            
        case .async:
            return InvocationRequest(
                model: ModelRef(
                    provider: "Mock",
                    modelID: "async-processor",
                    endpoint: "/process",
                    mode: "async"
                ),
                params: .object([
                    "task": .string("Complex data processing"),
                    "complexity": .number(8.0)
                ]),
                runKey: ULID.generate(),
                credentialID: UUID()
            )
        }
    }
}

// MARK: - Supporting Types

enum TestType: String, CaseIterable {
    case image = "image"
    case video = "video"
    case async = "async"
    
    var displayName: String {
        switch self {
        case .image: return "Image Generation"
        case .video: return "Video Generation"
        case .async: return "Async Processing"
        }
    }
    
    var iconName: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .async: return "clock.arrow.circlepath"
        }
    }
}

struct AdapterTestResult: Identifiable {
    let id: UUID
    let adapter: String
    let testType: TestType
    let status: String
    let duration: TimeInterval
    let billedUSD: Decimal?
    let errorMessage: String?
    let artifactCount: Int
    let timestamp: Date
    
    var isSuccess: Bool {
        return status == "succeeded"
    }
    
    var costDisplay: String {
        guard let billedUSD = billedUSD else { return "Free" }
        return String(format: "$%.4f", billedUSD as NSDecimalNumber)
    }
    
    var durationDisplay: String {
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

// MARK: - Supporting Views

struct AdapterCard: View {
    let adapter: CloudAdapter
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(adapter.provider)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Available: \(adapter.isAvailable ? "Yes" : "No")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(8)
        .onTapGesture {
            onTap()
        }
    }
}

struct TestResultRowView: View {
    let result: AdapterTestResult
    
    var body: some View {
        HStack {
            Image(systemName: result.testType.iconName)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.testType.displayName) - \(result.adapter)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(result.timestamp, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let errorMessage = result.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                HStack {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isSuccess ? .green : .red)
                    Text(result.status.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(result.isSuccess ? .green : .red)
                }
                
                Text(result.durationDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(result.costDisplay)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if result.artifactCount > 0 {
                    Text("\(result.artifactCount) artifacts")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct MockAdapterDemo_Previews: PreviewProvider {
    static var previews: some View {
        MockAdapterDemo()
    }
}
