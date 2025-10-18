import SwiftUI
import UIKit
import AVKit
import AVFoundation

struct ArtifactGalleryView: View {
    @ObservedObject var persistence: RunPersistence
    @SwiftUI.Binding var isPresented: Bool
    
    @State private var selectedArtifact: Artifact?
    @State private var diskArtifacts: [Artifact] = []
    
    private var artifactsMergedSorted: [Artifact] {
        // Merge by id or contentHash to avoid duplicates
        let persisted = persistence.getAllArtifacts()
        var byHash: [String: Artifact] = [:]
        for a in persisted { byHash[a.contentHash] = a }
        for a in diskArtifacts { byHash[a.contentHash] = byHash[a.contentHash] ?? a }
        return Array(byHash.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 12)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(artifactsMergedSorted) { artifact in
                        ArtifactTile(artifact: artifact)
                            .onTapGesture {
                                selectedArtifact = artifact
                            }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Artifacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(item: $selectedArtifact) { artifact in
                ArtifactPreviewSheet(artifact: artifact)
            }
        }
        .onAppear(perform: refreshFromDisk)
        .onReceive(persistence.$artifacts) { _ in
            // Refresh when artifacts list changes
            refreshFromDisk()
        }
    }
    
    private func refreshFromDisk() {
        diskArtifacts = ArtifactManager.shared.listAllArtifacts()
    }
}

private struct ArtifactTile: View {
    let artifact: Artifact
    @State private var thumbnail: UIImage?
    
    // Simple in-memory cache keyed by URI to avoid regenerating thumbnails repeatedly
    private static let cache = NSCache<NSString, UIImage>()
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
            
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .cornerRadius(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: artifact.isVideo ? "video" : artifact.iconName)
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text(artifact.displayName)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(12)
            }
        }
        .frame(height: 140)
        .onAppear(perform: loadThumbnailIfNeeded)
    }
    
    private func loadThumbnailIfNeeded() {
        let key = artifact.uri as NSString
        if let cached = Self.cache.object(forKey: key) {
            thumbnail = cached
            return
        }
        guard let url = URL(string: artifact.uri) else { return }
        if artifact.isImage {
            if url.isFileURL {
                if let img = UIImage(contentsOfFile: url.path) {
                    Self.cache.setObject(img, forKey: key)
                    thumbnail = img
                }
            } else {
                Task {
                    if let img = await fetchRemoteImage(url: url) {
                        Self.cache.setObject(img, forKey: key)
                        thumbnail = img
                    }
                }
            }
            return
        }
        if artifact.isVideo {
            Task.detached {
                let image = generateVideoThumbnail(url: url)
                if let image {
                    Self.cache.setObject(image, forKey: key)
                    await MainActor.run { thumbnail = image }
                }
            }
        }
    }
    
    private func generateVideoThumbnail(url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        do {
            let cg = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cg)
        } catch {
            return nil
        }
    }
}

private struct ArtifactPreviewSheet: View {
    let artifact: Artifact
    @State private var textContent: String?
    @State private var jsonContent: String?
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    
    var body: some View {
        VStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let text = textContent {
                ScrollView { Text(text).font(.body).padding() }
            } else if let json = jsonContent {
                ScrollView { Text(json).font(.system(.body, design: .monospaced)).padding() }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: artifact.iconName)
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(artifact.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding()
            }
            Spacer()
        }
        .onAppear(perform: loadPreview)
    }
    
    private func loadPreview() {
        guard let url = URL(string: artifact.uri) else { return }
        if artifact.isVideo {
            player = AVPlayer(url: url)
            return
        }
        if artifact.isImage {
            if url.isFileURL {
                image = UIImage(contentsOfFile: url.path)
            } else {
                Task {
                    if let img = await fetchRemoteImage(url: url) {
                        image = img
                    }
                }
            }
            return
        }
        if artifact.isJSON {
            if let data = try? Data(contentsOf: url),
               let object = try? JSONSerialization.jsonObject(with: data, options: []),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
               let str = String(data: pretty, encoding: .utf8) {
                jsonContent = str
                return
            }
        }
        if artifact.isText {
            if let data = try? Data(contentsOf: url),
               let str = String(data: data, encoding: .utf8) {
                textContent = str
                return
            }
        }
    }
}


fileprivate func fetchRemoteImage(url: URL) async -> UIImage? {
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    } catch {
        return nil
    }
}


