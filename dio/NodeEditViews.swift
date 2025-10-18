import SwiftUI

// MARK: - Node Edit Views

// Sheet for editing nodes
struct NodeEditSheet: View {
    let node: Node
    @SwiftUI.Binding var isPresented: Bool
    let onSave: (Node) -> Void
    let onDelete: (() -> Void)?
    
    @State private var tempNode: Node
    @FocusState private var isTextFieldFocused: Bool
    @State private var isConfirmingDelete: Bool = false
    @State private var commitEdits: (() -> Void)? = nil
    
    init(
        node: Node,
        isPresented: SwiftUI.Binding<Bool>,
        onSave: @escaping (Node) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.node = node
        self._isPresented = isPresented
        self.onSave = onSave
        self._tempNode = State(initialValue: node)
        self.isConfirmingDelete = false
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 10) {
            // Header with title and save button
            HStack {
                Text(node.kind.displayName)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    commitEdits?()
                    onSave(tempNode)
                    isPresented = false
                }
                .fontWeight(.medium)
            }
            
            // Content based on node type
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch node.kind {
                    case .textPrompt:
                        TextPromptEditView(
                            node: $tempNode,
                            isTextFieldFocused: $isTextFieldFocused
                        )
                    case .imageGeneration:
                        ImageGenerationEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .seedreamEdit:
                        SeedDreamEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .openaiSora:
                        OpenaiSoraEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .imageToVideo:
                        ImageToVideoEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .seedanceImageToVideo:
                        SeedanceImageToVideoEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .wanAnimateMove:
                        WanAnimateMoveEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    case .wanAnimateReplace:
                        WanAnimateMoveEditView(
                            node: $tempNode,
                            onRegisterCommit: { closure in
                                self.commitEdits = closure
                            }
                        )
                    default:
                        Text("Unknown node type")
                           .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if let onDelete = onDelete {
                        Button(role: isConfirmingDelete ? .destructive : nil) {
                            if isConfirmingDelete {
                                onDelete()
                                isPresented = false
                            } else {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isConfirmingDelete = true
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isConfirmingDelete ? "trash.fill" : "trash")
                                    .font(.system(size: 16))
                                Text(isConfirmingDelete ? "Confirm Remove?" : "Remove Node")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isConfirmingDelete ? Color.red : Color(.systemGray5))
                            .foregroundColor(isConfirmingDelete ? .white : .primary)
                            .cornerRadius(12)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .background(Color(.systemBackground))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                isTextFieldFocused = true
            }
        }
    }
}

// MARK: - Edit View Components

// Text Prompt Edit Sheet
struct TextPromptEditSheet: View {
    let node: Node
    @SwiftUI.Binding var isPresented: Bool
    let onSave: (Node) -> Void
    
    @State private var tempNode: Node
    @FocusState private var isTextFieldFocused: Bool
    
    init(node: Node, isPresented: SwiftUI.Binding<Bool>, onSave: @escaping (Node) -> Void) {
        self.node = node
        self._isPresented = isPresented
        self.onSave = onSave
        self._tempNode = State(initialValue: node)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Prompt")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button("Done") {
                    onSave(tempNode)
                    isPresented = false
                }
                .fontWeight(.medium)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextPromptEditView(node: $tempNode, isTextFieldFocused: $isTextFieldFocused)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            print("TextPromptEditSheet appeared")
            print("tempNode text: \(tempNode.getArg("/text", as: String.self) ?? "nil")")
            print("TextPromptEditSheet body is being rendered")
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                isTextFieldFocused = true
            }
        }
    }
}

// Text Prompt Edit View
struct TextPromptEditView: View {
    @SwiftUI.Binding var node: Node
    @FocusState.Binding var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: SwiftUI.Binding(
                    get: { 
                        node.getArg("/text", as: String.self) ?? ""
                    },
                    set: { newValue in
                        node.setArg("/text", value: newValue)
                    }
                ))
                .focused($isTextFieldFocused)
                .frame(minHeight: 120)
                .padding(0)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if (node.getArg("/text", as: String.self) ?? "").isEmpty {
                    Text("Your prompt goes here...")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// Image Generation Edit View
struct ImageGenerationEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    @State private var localPrompt: String = ""
    
    private enum ImageSizePreset: String, CaseIterable, Identifiable {
        case square_hd
        case square
        case portrait_4_3
        case portrait_16_9
        case landscape_4_3
        case landscape_16_9
        var id: String { rawValue }
        var label: String {
            switch self {
            case .square_hd: return "Square HD (1024x1024)"
            case .square: return "Square (512x512)"
            case .portrait_4_3: return "Portrait 4:3 (768x1024)"
            case .portrait_16_9: return "Portrait 16:9 (720x1280)"
            case .landscape_4_3: return "Landscape 4:3 (1024x768)"
            case .landscape_16_9: return "Landscape 16:9 (1280x720)"
            }
        }
        // Representative dimensions used for downstream mapping if consumers read /size
        var widthHeight: (Int, Int) {
            switch self {
            case .square: return (512, 512)
            case .square_hd: return (1024, 1024)
            case .portrait_4_3: return (768, 1024)
            case .portrait_16_9: return (720, 1280)
            case .landscape_4_3: return (1024, 768)
            case .landscape_16_9: return (1280, 720)
            }
        }
    }
    @State private var localSizePreset: ImageSizePreset = .landscape_4_3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $localPrompt)
                        .frame(minHeight: 80)
                        .padding(0)
                    if localPrompt.isEmpty {
                        Text("Your prompt goes here...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }
        
            HStack(spacing: 12) {
                Text("Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Picker("Size", selection: $localSizePreset) {
                    ForEach(ImageSizePreset.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .onAppear {
            // Initialize local state from node
            self.localPrompt = node.getArg("/prompt", as: String.self) ?? ""
            // Infer preset from size if present; default to landscape_4_3
            let width = Int(node.getArg("/size/width", as: Double.self) ?? 1024)
            let height = Int(node.getArg("/size/height", as: Double.self) ?? 768)
            if width == 1024 && height == 1024 { self.localSizePreset = .square_hd }
            else if width == 512 && height == 512 { self.localSizePreset = .square }
            else if width == 768 && height == 1024 { self.localSizePreset = .portrait_4_3 }
            else if width == 720 && height == 1280 { self.localSizePreset = .portrait_16_9 }
            else if width == 1024 && height == 768 { self.localSizePreset = .landscape_4_3 }
            else if width == 1280 && height == 720 { self.localSizePreset = .landscape_16_9 }
            else { self.localSizePreset = .landscape_4_3 }

            // Register commit to apply prompt and size
            onRegisterCommit {
                node.setArg("/prompt", value: self.localPrompt)
                let (w, h) = self.localSizePreset.widthHeight
                node.setArg("/size/width", value: Double(w))
                node.setArg("/size/height", value: Double(h))
            }
        }
    }
}

// SeedDream v4 Edit View
struct SeedDreamEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    @State private var localPrompt: String = ""
    @State private var localNumImages: Int = 1
    @State private var localMaxImages: Int = 1
    @State private var localWidth: Int = 2048
    @State private var localHeight: Int = 2048
    // @State private var localEnableSafety: Bool = false
    // @State private var setSeedManually: Bool = false
    // @State private var localSeed: Int = 0

    private enum SeedDreamSizePreset: String, CaseIterable, Identifiable {
        case squareHD
        case portrait_9_16
        case landscape_16_9
        var id: String { rawValue }
        var label: String {
            switch self {
            case .squareHD: return "Square HD (2048x2048)"
            case .portrait_9_16: return "Portrait 9:16 (720x1280)"
            case .landscape_16_9: return "Landscape 16:9 (1280x720)"
            }
        }
        var widthHeight: (Int, Int) {
            switch self {
            case .squareHD: return (2048, 2048)
            case .portrait_9_16: return (720, 1280)
            case .landscape_16_9: return (1280, 720)
            }
        }
    }
    @State private var selectedPreset: SeedDreamSizePreset = .squareHD

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $localPrompt)
                        .frame(minHeight: 80)
                        .padding(0)
                    if localPrompt.isEmpty {
                        Text("Describe how to edit the input images…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Size preset
            HStack(spacing: 12) {
                Text("Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Picker("Size", selection: $selectedPreset) {
                    ForEach(SeedDreamSizePreset.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            // Counts
            VStack(alignment: .leading, spacing: 8) {
                Text("Images per generation")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Stepper(value: $localNumImages, in: 1...6) {
                    Text("Num images: \(localNumImages)")
                }
                Stepper(value: $localMaxImages, in: 1...6) {
                    Text("Max images: \(localMaxImages)")
                }
            }

//            // Safety and seed
//            Toggle("Enable Safety Checker", isOn: $localEnableSafety)
//            VStack(alignment: .leading, spacing: 8) {
//                Toggle("Set Seed", isOn: $setSeedManually)
//                if setSeedManually {
//                    Stepper(value: $localSeed, in: 0...1_000_000) {
//                        Text("Seed: \(localSeed)")
//                    }
//                }
//            }
        }
        .onAppear {
            // Initialize local state from node args
            self.localPrompt = node.getArg("/prompt", as: String.self) ?? ""
            self.localNumImages = max(1, min(6, node.getArg("/num_images", as: Int.self) ?? 1))
            self.localMaxImages = max(1, min(6, node.getArg("/max_images", as: Int.self) ?? 1))
            self.localWidth = Int(node.getArg("/image_size/width", as: Double.self) ?? 2048)
            self.localHeight = Int(node.getArg("/image_size/height", as: Double.self) ?? 2048)
            // Infer preset from current size
            if localWidth == 2048 && localHeight == 2048 { self.selectedPreset = .squareHD }
            else if localWidth == 720 && localHeight == 1280 { self.selectedPreset = .portrait_9_16 }
            else if localWidth == 1280 && localHeight == 720 { self.selectedPreset = .landscape_16_9 }
            else { self.selectedPreset = .squareHD }
            // self.localEnableSafety = node.getArg("/enable_safety_checker", as: Bool.self) ?? true
            // if let seed = node.getArg("/seed", as: Int.self) { self.setSeedManually = true; self.localSeed = seed } else { self.setSeedManually = false }

            onRegisterCommit {
                node.setArg("/prompt", value: self.localPrompt)
                node.setArg("/num_images", value: self.localNumImages)
                node.setArg("/max_images", value: self.localMaxImages)
                let (w, h) = self.selectedPreset.widthHeight
                node.setArg("/image_size/width", value: Double(w))
                node.setArg("/image_size/height", value: Double(h))
//                node.setArg("/enable_safety_checker", value: self.localEnableSafety)
//                if self.setSeedManually { node.setArg("/seed", value: self.localSeed) }
            }
        }
    }
}

// Video Generation Edit View (OpenAI Sora)
struct OpenaiSoraEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    @State private var localPrompt: String = ""
    @State private var localDurationSeconds: Int = 4

    private enum VideoSizeOption: String, CaseIterable, Identifiable {
        case portrait
        case landscape
        var id: String { rawValue }
        var label: String {
            switch self {
            case .portrait: return "Portrait"
            case .landscape: return "Landscape"
            }
        }
        var widthHeight: (Int, Int) {
            switch self {
            case .portrait: return (720, 1280)
            case .landscape: return (1280, 720)
            }
        }
    }
    @State private var localSize: VideoSizeOption = .landscape

    private enum VideoModelOption: String, CaseIterable, Identifiable {
        case sora2 = "sora-2"
        case sora2Pro = "sora-2-pro"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sora2: return "sora-2"
            case .sora2Pro: return "sora-2-pro"
            }
        }
    }
    @State private var localModel: VideoModelOption = .sora2
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $localPrompt)
                        .frame(minHeight: 80)
                        .padding(0)
                    if localPrompt.isEmpty {
                        Text("Your prompt goes here...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("Size", selection: $localSize) {
                    ForEach(VideoSizeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                let wh = localSize.widthHeight
                Text("Resolution: \(wh.0) x \(wh.1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Stepper(value: $localDurationSeconds, in: 4...10) {
                    Text("\(localDurationSeconds) seconds")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Model")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("Model", selection: $localModel) {
                    ForEach(VideoModelOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Input Reference (optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                let inputRef = node.getArg("/input_reference", as: String.self) ?? ""
                TextField("Image URL or file URL", text: SwiftUI.Binding(
                    get: { inputRef },
                    set: { newValue in
                        node.setArg("/input_reference", value: newValue)
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("Must match target resolution; supports jpeg/png/webp")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            // Initialize local state from node
            let prompt = node.getArg("/prompt", as: String.self) ?? ""
            self.localPrompt = prompt

            let seconds = Int(node.getArg("/seconds", as: Double.self) ?? 4)
            self.localDurationSeconds = min(10, max(4, seconds))

            let modelRaw = node.getArg("/model", as: String.self) ?? VideoModelOption.sora2.rawValue
            if let parsedModel = VideoModelOption(rawValue: modelRaw) {
                self.localModel = parsedModel
            } else {
                self.localModel = .sora2
            }

            let width = Int(node.getArg("/size/width", as: Double.self) ?? 1280)
            let height = Int(node.getArg("/size/height", as: Double.self) ?? 720)
            if width == 720 && height == 1280 {
                self.localSize = .portrait
            } else if width == 1280 && height == 720 {
                self.localSize = .landscape
            } else {
                self.localSize = width < height ? .portrait : .landscape
            }

            // Register commit closure to apply current local edits to the node when Done is tapped
            onRegisterCommit {
                node.setArg("/prompt", value: self.localPrompt)
                node.setArg("/seconds", value: Double(self.localDurationSeconds))
                node.setArg("/model", value: self.localModel.rawValue)
                let (w, h) = self.localSize.widthHeight
                node.setArg("/size/width", value: Double(w))
                node.setArg("/size/height", value: Double(h))
            }
        }
    }
}

// Image → Video (FAL Kling) Edit View
struct ImageToVideoEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    @State private var localPrompt: String = ""
    @State private var localImageURL: String = ""
    @State private var localDuration: String = "5" // "5" or "10"
    @State private var localCfgScale: Double = 0.5 // 0..1
    @State private var localNegative: String = "blur, distort, and low quality"

    private let durationOptions: [String] = ["5", "10"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $localPrompt)
                        .frame(minHeight: 80)
                        .padding(0)
                    if localPrompt.isEmpty {
                        Text("Describe the motion you want...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            // // Image URL
            // VStack(alignment: .leading, spacing: 8) {
            //     Text("Image URL")
            //         .font(.subheadline)
            //         .fontWeight(.medium)
            //     TextField("https://... (jpeg/png/webp)", text: $localImageURL)
            //         .textFieldStyle(RoundedBorderTextFieldStyle())
            // }

            // Duration (5 or 10)
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("Duration", selection: $localDuration) {
                    ForEach(durationOptions, id: \.self) { opt in
                        Text("\(opt) seconds").tag(opt)
                    }
                }
                .pickerStyle(.segmented)
            }

            // // CFG Scale (0..1)
            // VStack(alignment: .leading, spacing: 8) {
            //     HStack {
            //         Text("CFG Scale")
            //             .font(.subheadline)
            //             .fontWeight(.medium)
            //         Spacer()
            //         Text(String(format: "%.2f", localCfgScale))
            //             .font(.caption)
            //             .foregroundStyle(.secondary)
            //     }
            //     Slider(value: $localCfgScale, in: 0...1, step: 0.01)
            // }

            // // Negative Prompt
            // VStack(alignment: .leading, spacing: 8) {
            //     Text("Negative Prompt")
            //         .font(.subheadline)
            //         .fontWeight(.medium)
            //     TextEditor(text: $localNegative)
            //         .frame(minHeight: 60)
            //         .padding(0)
            // }
        }
        .onAppear {
            // Initialize local state from node args
            self.localPrompt = node.getArg("/prompt", as: String.self) ?? ""
            self.localImageURL = node.getArg("/image_url", as: String.self) ?? ""
            self.localDuration = node.getArg("/duration", as: String.self) ?? "5"
            self.localCfgScale = node.getArg("/cfg_scale", as: Double.self) ?? 0.5
            self.localNegative = node.getArg("/negative_prompt", as: String.self) ?? "blur, distort, and low quality"

            // Register commit closure
            onRegisterCommit {
                node.setArg("/prompt", value: self.localPrompt)
                node.setArg("/image_url", value: self.localImageURL)
                node.setArg("/duration", value: self.localDuration)
                node.setArg("/cfg_scale", value: self.localCfgScale)
                node.setArg("/negative_prompt", value: self.localNegative)
            }
        }
    }
}

// Seedance Image → Video Edit View
struct SeedanceImageToVideoEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    @State private var localPrompt: String = ""
    @State private var localImageURL: String = ""
    @State private var localDuration: String = "5" // 3..12
    @State private var localAspect: String = "auto"
    @State private var localResolution: String = "720p"
    @State private var localCameraFixed: Bool = false
    @State private var localEnableSafety: Bool = true
    @State private var setSeedManually: Bool = false
    @State private var localSeed: Int = 0
    @State private var localEndImageURL: String = ""

    private let durationOptions: [String] = ["3","4","5","6","7","8","9","10","11","12"]
    private let aspectOptions: [String] = ["21:9","16:9","4:3","1:1","3:4","9:16","auto"]
    private let resolutionOptions: [String] = ["480p","720p","1080p"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Prompt
            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt").font(.subheadline).fontWeight(.medium)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $localPrompt).frame(minHeight: 80).padding(0)
                    if localPrompt.isEmpty {
                        Text("Describe the motion you want...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
            }

            // Image URL hidden: now provided via input port

            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration").font(.subheadline).fontWeight(.medium)
                Picker("Duration", selection: $localDuration) {
                    ForEach(durationOptions, id: \.self) { opt in
                        Text("\(opt) seconds").tag(opt)
                    }
                }.pickerStyle(.menu)
            }

            // Aspect ratio
            VStack(alignment: .leading, spacing: 8) {
                Text("Aspect Ratio").font(.subheadline).fontWeight(.medium)
                Picker("Aspect Ratio", selection: $localAspect) {
                    ForEach(aspectOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }.pickerStyle(.menu)
            }

            // Resolution
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution").font(.subheadline).fontWeight(.medium)
                Picker("Resolution", selection: $localResolution) {
                    ForEach(resolutionOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }.pickerStyle(.segmented)
            }

            // Camera fixed only (safety hidden)
            Toggle("Fix Camera Position", isOn: $localCameraFixed)

            // Seed controls hidden

            // End image URL hidden: now provided via input port
        }
        .onAppear {
            self.localPrompt = node.getArg("/prompt", as: String.self) ?? ""
            self.localImageURL = node.getArg("/image_url", as: String.self) ?? ""
            self.localDuration = node.getArg("/duration", as: String.self) ?? "5"
            self.localAspect = node.getArg("/aspect_ratio", as: String.self) ?? "auto"
            self.localResolution = node.getArg("/resolution", as: String.self) ?? "720p"
            self.localCameraFixed = node.getArg("/camera_fixed", as: Bool.self) ?? false
            self.localEnableSafety = node.getArg("/enable_safety_checker", as: Bool.self) ?? true
            // Seed UI hidden; still read if present but do not expose controls
            if let seed = node.getArg("/seed", as: Int.self) { self.setSeedManually = true; self.localSeed = seed } else { self.setSeedManually = false }
            self.localEndImageURL = node.getArg("/end_image_url", as: String.self) ?? ""

            onRegisterCommit {
                node.setArg("/prompt", value: self.localPrompt)
                // image_url provided via input port
                node.setArg("/duration", value: self.localDuration)
                node.setArg("/aspect_ratio", value: self.localAspect)
                node.setArg("/resolution", value: self.localResolution)
                node.setArg("/camera_fixed", value: self.localCameraFixed)
                // safety & seed hidden from UI
                // end_image_url provided via input port
            }
        }
    }
}


// WAN Animate Move Edit View (FAL WAN)
struct WanAnimateMoveEditView: View {
    @SwiftUI.Binding var node: Node
    let onRegisterCommit: (@escaping () -> Void) -> Void

    private let resolutionOptions: [String] = ["480p", "580p", "720p"]
    private let qualityOptions: [String] = ["low", "medium", "high", "maximum"]
    private let writeModeOptions: [String] = ["fast", "balanced", "small"]

    @State private var localResolution: String = "480p"
    @State private var localSteps: Int = 20
    @State private var localEnableSafety: Bool = false
    @State private var localEnableOutputSafety: Bool = false
    @State private var localShift: Double = 5.0
    @State private var localQuality: String = "high"
    @State private var localWriteMode: String = "balanced"
    @State private var setSeedManually: Bool = false
    @State private var localSeed: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Resolution
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution").font(.subheadline).fontWeight(.medium)
                Picker("Resolution", selection: $localResolution) {
                    ForEach(resolutionOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }.pickerStyle(.segmented)
            }

            // Steps
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps").font(.subheadline).fontWeight(.medium)
                Stepper(value: $localSteps, in: 2...40) {
                    Text("\(localSteps) steps")
                }
            }

            // Seed
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Set Seed", isOn: $setSeedManually)
                if setSeedManually {
                    Stepper(value: $localSeed, in: 0...1_000_000) {
                        Text("Seed: \(localSeed)")
                    }
                }
            }

            // Safety
            Toggle("Enable Safety Checker", isOn: $localEnableSafety)
            Toggle("Enable Output Safety Checker", isOn: $localEnableOutputSafety)

            // Shift
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shift")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(String(format: "%.1f", localShift))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: $localShift, in: 1.0...10.0, step: 0.1)
            }

            // Quality
            VStack(alignment: .leading, spacing: 8) {
                Text("Video Quality").font(.subheadline).fontWeight(.medium)
                Picker("Quality", selection: $localQuality) {
                    ForEach(qualityOptions, id: \.self) { opt in
                        Text(opt.capitalized).tag(opt)
                    }
                }.pickerStyle(.menu)
            }

            // Write Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Write Mode").font(.subheadline).fontWeight(.medium)
                Picker("Write Mode", selection: $localWriteMode) {
                    ForEach(writeModeOptions, id: \.self) { opt in
                        Text(opt.capitalized).tag(opt)
                    }
                }.pickerStyle(.menu)
            }
        }
        .onAppear {
            // Initialize from node args
            self.localResolution = node.getArg("/resolution", as: String.self) ?? "480p"
            self.localSteps = max(2, min(40, node.getArg("/num_inference_steps", as: Int.self) ?? 20))
            self.localEnableSafety = node.getArg("/enable_safety_checker", as: Bool.self) ?? false
            self.localEnableOutputSafety = node.getArg("/enable_output_safety_checker", as: Bool.self) ?? false
            self.localShift = max(1.0, min(10.0, node.getArg("/shift", as: Double.self) ?? 5.0))
            self.localQuality = node.getArg("/video_quality", as: String.self) ?? "high"
            self.localWriteMode = node.getArg("/video_write_mode", as: String.self) ?? "balanced"
            if let seed = node.getArg("/seed", as: Int.self) { self.setSeedManually = true; self.localSeed = seed } else { self.setSeedManually = false }

            onRegisterCommit {
                node.setArg("/resolution", value: self.localResolution)
                node.setArg("/num_inference_steps", value: self.localSteps)
                node.setArg("/enable_safety_checker", value: self.localEnableSafety)
                node.setArg("/enable_output_safety_checker", value: self.localEnableOutputSafety)
                node.setArg("/shift", value: self.localShift)
                node.setArg("/video_quality", value: self.localQuality)
                node.setArg("/video_write_mode", value: self.localWriteMode)
                if self.setSeedManually {
                    node.setArg("/seed", value: self.localSeed)
                }
            }
        }
    }
}

