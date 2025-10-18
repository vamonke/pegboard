# Phase 3: Cloud Adapter Layer

## Overview
Build the cloud integration layer that connects your execution engine to real AI providers like FAL, WaveSpeed, and other cloud services. This phase transforms your mock system into a production-ready platform.

## Current State (Post-Phase 2)
✅ **Execution Engine**: Topological execution with run tracking  
✅ **Run & Artifact System**: Immutable execution records with proper storage  
✅ **Mock Adapter**: Working simulation of cloud providers  
✅ **Run History UI**: Visual feedback and result management  
✅ **Error Handling**: Proper error states and user feedback  

## Phase 3 Goals
1. **Real Cloud Adapters**: FAL, WaveSpeed, and other provider integrations
2. **Credential Management**: Secure API key storage and management
3. **Rate Limiting & Retry**: Production-ready error handling and backoff
4. **Async Job Polling**: Handle long-running operations properly
5. **Cost Tracking**: Real-time cost monitoring and billing
6. **Provider Selection**: UI for choosing and configuring providers

---

## 3.1 Credential Management System (Week 1)

### Core Data Structures
```swift
// Secure credential storage
struct Credential: Codable, Identifiable {
    let id: UUID
    let provider: String           // "FAL", "WaveSpeed", "OpenAI"
    let keyRef: String            // Keychain reference
    let displayName: String
    let createdAt: Date
    let lastUsed: Date?
    var isActive: Bool
}

// Provider configuration
struct ProviderConfig: Codable {
    let name: String
    let displayName: String
    let baseURL: String
    let supportedModels: [ModelRef]
    let rateLimits: RateLimitConfig
    let pricing: PricingConfig
}

struct RateLimitConfig: Codable {
    let requestsPerMinute: Int
    let requestsPerHour: Int
    let requestsPerDay: Int
    let burstLimit: Int
}

struct PricingConfig: Codable {
    let costPerRequest: Decimal
    let costPerToken: Decimal?
    let costPerImage: Decimal?
    let costPerSecond: Decimal?
}
```

### Keychain Integration
```swift
class CredentialManager {
    func storeCredential(provider: String, apiKey: String) throws -> String
    func retrieveCredential(keyRef: String) throws -> String
    func deleteCredential(keyRef: String) throws
    func listCredentials() -> [Credential]
}
```

### Tasks
- [ ] Create credential storage system with Keychain
- [ ] Build credential management UI (add/edit/delete)
- [ ] Implement provider configuration system
- [ ] Add credential validation and testing
- [ ] Create secure credential sharing between app launches

---

## 3.2 FAL Adapter Implementation (Week 2)

### FAL API Integration
```swift
class FALAdapter: CloudAdapter {
    let provider = "FAL"
    private let credentialManager: CredentialManager
    private let rateLimiter: RateLimiter
    
    func invoke(_ request: InvocationRequest) async throws -> InvocationResponse {
        // 1. Validate credentials
        // 2. Apply rate limiting
        // 3. Make API call to FAL
        // 4. Handle response and errors
        // 5. Return standardized response
    }
    
    func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse {
        // Poll FAL for async job completion
    }
}
```

### FAL-Specific Models
```swift
// FAL API request/response models
struct FALRequest: Codable {
    let model: String
    let inputs: [String: AnyCodable]
    let webhookUrl: String?
    let webhookSecret: String?
}

struct FALResponse: Codable {
    let requestId: String
    let status: String
    let logs: [String]?
    let metrics: FALMetrics?
    let output: [String: AnyCodable]?
}

struct FALMetrics: Codable {
    let predictTime: Double?
    let queueTime: Double?
    let totalTime: Double?
}
```

### Supported FAL Models
- [ ] **Image Generation**: SDXL, Flux, Stable Diffusion
- [ ] **Video Generation**: AnimateDiff, SVD
- [ ] **Text Generation**: Llama, Mistral
- [ ] **Image Processing**: Upscaling, Inpainting, Outpainting

### Tasks
- [ ] Implement FAL API client with proper authentication
- [ ] Add support for sync and async endpoints
- [ ] Handle FAL-specific error codes and messages
- [ ] Implement proper retry logic for FAL rate limits
- [ ] Add cost tracking for FAL usage
- [ ] Create FAL model configuration system

---

## 3.3 WaveSpeed Adapter Implementation (Week 3)

### WaveSpeed API Integration
```swift
class WaveSpeedAdapter: CloudAdapter {
    let provider = "WaveSpeed"
    private let credentialManager: CredentialManager
    private let rateLimiter: RateLimiter
    
    func invoke(_ request: InvocationRequest) async throws -> InvocationResponse {
        // WaveSpeed-specific implementation
    }
    
    func poll(jobID: String, credentialID: UUID) async throws -> InvocationResponse {
        // WaveSpeed polling implementation
    }
}
```

### WaveSpeed-Specific Features
- [ ] **Video Generation**: High-quality video synthesis
- [ ] **Real-time Processing**: Low-latency image generation
- [ ] **Custom Models**: User-trained model support
- [ ] **Batch Processing**: Multiple requests in single call

### Tasks
- [ ] Implement WaveSpeed API client
- [ ] Add WaveSpeed-specific error handling
- [ ] Implement video generation workflows
- [ ] Add WaveSpeed cost tracking
- [ ] Create WaveSpeed model configuration

---

## 3.4 Rate Limiting & Retry System (Week 4)

### Rate Limiting Engine
```swift
class RateLimiter {
    private var requestCounts: [String: [Date]] = [:]
    private let config: RateLimitConfig
    
    func canMakeRequest(for provider: String) -> Bool
    func recordRequest(for provider: String)
    func getRetryAfter(for provider: String) -> TimeInterval?
}

class RetryManager {
    func executeWithRetry<T>(
        operation: @escaping () async throws -> T,
        maxRetries: Int = 3,
        backoffStrategy: BackoffStrategy = .exponential
    ) async throws -> T
}

enum BackoffStrategy {
    case linear(baseDelay: TimeInterval)
    case exponential(baseDelay: TimeInterval, multiplier: Double)
    case jittered(baseDelay: TimeInterval, jitterRange: ClosedRange<Double>)
}
```

### Error Handling
```swift
enum AdapterError: Error {
    case invalidCredentials
    case rateLimitExceeded(retryAfter: TimeInterval)
    case quotaExceeded
    case modelNotFound
    case invalidParameters([String])
    case networkError(Error)
    case timeout
    case unknown(String)
}
```

### Tasks
- [ ] Implement token bucket rate limiting
- [ ] Add exponential backoff with jitter
- [ ] Handle provider-specific rate limit headers
- [ ] Implement circuit breaker pattern
- [ ] Add retry UI feedback for users
- [ ] Create rate limit monitoring and alerts

---

## 3.5 Cost Tracking & Billing (Week 5)

### Cost Calculation System
```swift
class CostTracker {
    func calculateCost(for run: Run, response: InvocationResponse) -> Decimal
    func trackUsage(for provider: String, cost: Decimal)
    func getTotalCost(for timeRange: DateInterval) -> Decimal
    func getCostBreakdown(by provider: String) -> [String: Decimal]
}

struct CostBreakdown: Codable {
    let totalCost: Decimal
    let byProvider: [String: Decimal]
    let byModel: [String: Decimal]
    let byTimeRange: [DateInterval: Decimal]
}
```

### Billing UI Components
```swift
struct CostDashboardView: View {
    @State private var costBreakdown: CostBreakdown
    @State private var selectedTimeRange: DateInterval
    
    var body: some View {
        // Cost charts, provider breakdown, usage trends
    }
}

struct RunCostView: View {
    let run: Run
    
    var body: some View {
        // Individual run cost display
    }
}
```

### Tasks
- [ ] Implement real-time cost calculation
- [ ] Add cost tracking to all adapters
- [ ] Create cost dashboard UI
- [ ] Add cost alerts and limits
- [ ] Implement cost export functionality
- [ ] Add cost prediction for pending runs

---

## 3.6 Provider Selection & Configuration UI (Week 6)

### Provider Management UI
```swift
struct ProviderSelectionView: View {
    @State private var availableProviders: [ProviderConfig]
    @State private var selectedProvider: String?
    @State private var credentials: [Credential]
    
    var body: some View {
        // Provider list, credential management, model selection
    }
}

struct ModelConfigurationView: View {
    let provider: String
    @State private var availableModels: [ModelRef]
    @State private var selectedModel: ModelRef?
    
    var body: some View {
        // Model selection, parameter configuration, testing
    }
}
```

### Node Configuration Updates
```swift
struct NodeProviderSelector: View {
    @Binding var node: Node
    @State private var availableProviders: [String]
    @State private var selectedProvider: String
    
    var body: some View {
        // Provider selection for individual nodes
    }
}
```

### Tasks
- [ ] Create provider discovery system
- [ ] Build provider selection UI
- [ ] Add model configuration interface
- [ ] Implement provider testing functionality
- [ ] Add provider-specific parameter validation
- [ ] Create provider comparison tools

---

## 3.7 Advanced Features (Week 7)

### Webhook Support
```swift
class WebhookManager {
    func registerWebhook(for runID: UUID, url: URL) async throws
    func handleWebhook(payload: Data, signature: String) async throws
    func verifyWebhookSignature(payload: Data, signature: String, secret: String) -> Bool
}
```

### Batch Processing
```swift
class BatchProcessor {
    func createBatch(requests: [InvocationRequest]) async throws -> BatchJob
    func pollBatch(jobID: String) async throws -> BatchStatus
    func cancelBatch(jobID: String) async throws
}
```

### Tasks
- [ ] Implement webhook system for async operations
- [ ] Add batch processing capabilities
- [ ] Create provider health monitoring
- [ ] Add automatic failover between providers
- [ ] Implement provider performance analytics
- [ ] Add custom model upload support

---

## Success Criteria

### Functional Requirements
- [ ] Can execute real workflows with FAL and WaveSpeed
- [ ] Proper credential management with Keychain
- [ ] Rate limiting prevents API quota exhaustion
- [ ] Cost tracking shows accurate billing information
- [ ] Provider selection works seamlessly
- [ ] Async operations complete successfully

### Technical Requirements
- [ ] Clean adapter pattern for easy provider addition
- [ ] Proper error handling with user-friendly messages
- [ ] Efficient rate limiting with minimal overhead
- [ ] Secure credential storage and transmission
- [ ] Scalable to multiple concurrent providers
- [ ] Production-ready logging and monitoring

### User Experience
- [ ] Easy provider setup and configuration
- [ ] Clear cost visibility and control
- [ ] Intuitive provider selection
- [ ] Helpful error messages and recovery
- [ ] Fast execution with real providers
- [ ] Reliable async operation handling

---

## Implementation Order

1. **Week 1**: Credential management system
2. **Week 2**: FAL adapter implementation
3. **Week 3**: WaveSpeed adapter implementation
4. **Week 4**: Rate limiting and retry system
5. **Week 5**: Cost tracking and billing
6. **Week 6**: Provider selection UI
7. **Week 7**: Advanced features and polish

---

## Provider-Specific Considerations

### FAL
- **Strengths**: Fast image generation, good model variety
- **Limitations**: Rate limits, async-only for some models
- **Pricing**: Pay-per-request model
- **Best For**: Image generation, quick prototyping

### WaveSpeed
- **Strengths**: High-quality video, real-time processing
- **Limitations**: Higher costs, limited model selection
- **Pricing**: Time-based and output-based
- **Best For**: Video generation, production workflows

### Future Providers
- **OpenAI**: GPT models, DALL-E
- **Anthropic**: Claude models
- **Google**: Vertex AI, Imagen
- **Stability AI**: Stable Diffusion, Stable Video

---

## Security Considerations

### API Key Management
- [ ] Store keys in iOS Keychain
- [ ] Never log or expose keys in plain text
- [ ] Implement key rotation support
- [ ] Add key validation and testing

### Network Security
- [ ] Use HTTPS for all API calls
- [ ] Implement certificate pinning
- [ ] Add request signing where required
- [ ] Handle network timeouts gracefully

### Data Privacy
- [ ] Minimize data sent to providers
- [ ] Implement data retention policies
- [ ] Add user consent for data sharing
- [ ] Provide data deletion capabilities

---

## Next Steps for New Conversation

1. **Start with credential management** - foundation for all providers
2. **Implement FAL first** - most straightforward integration
3. **Add rate limiting early** - prevents quota issues
4. **Build incrementally** - one provider at a time
5. **Test thoroughly** - real APIs have edge cases

## Key Files to Create/Modify

### New Files
- `CredentialManager.swift` - Secure credential storage
- `FALAdapter.swift` - FAL API integration
- `WaveSpeedAdapter.swift` - WaveSpeed API integration
- `RateLimiter.swift` - Rate limiting and retry logic
- `CostTracker.swift` - Cost calculation and tracking
- `ProviderConfig.swift` - Provider configuration models
- `ProviderSelectionView.swift` - Provider management UI

### Modified Files
- `ExecutionEngine.swift` - Add real adapter support
- `ContentView.swift` - Add provider selection
- `NodeEditViews.swift` - Add provider configuration
- `RunModels.swift` - Add cost tracking fields

---

## Questions to Consider

1. **Provider Priority**: Which providers to implement first?
2. **Cost Limits**: Should users set spending limits?
3. **Failover**: Automatic provider switching on failure?
4. **Caching**: Cache results to reduce API calls?
5. **Analytics**: What metrics to track for optimization?

This plan gives you a comprehensive roadmap for Phase 3. Start the new conversation with this context and begin with credential management!
