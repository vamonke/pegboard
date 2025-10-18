import SwiftUI

// MARK: - Port Selection Modal (unused for now)

struct PortSelectionModal: View {
    let sourcePort: PortDef
    let sourceNode: Node
    let availableInputPorts: [(Node, PortDef)]
    let onCancel: () -> Void
    let onSelect: (Node, PortDef) -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header with source port info
                sourcePortInfo
                
                Divider()
                
                // Available input ports
                availablePortsSection
                
                Spacer()
            }
            .padding()
            .navigationTitle("Connect To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
    
    // MARK: - Source Port Info
    
    private var sourcePortInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From")
                .font(.headline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Source port icon
                Circle()
                    .fill(portColor(for: sourcePort))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: sourcePort.dtype.iconName)
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourcePort.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("\(sourceNode.kind.displayName) • \(sourcePort.dtype.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    // MARK: - Available Ports Section
    
    private var availablePortsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Select an input port to connect to:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if availableInputPorts.isEmpty {
                Text("No compatible input ports available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(availableInputPorts, id: \.1.id) { node, port in
                        inputPortRow(node: node, port: port)
                    }
                }
            }
        }
    }
    
    private func inputPortRow(node: Node, port: PortDef) -> some View {
        Button(action: {
            onSelect(node, port)
            onCancel()
        }) {
            HStack(spacing: 12) {
                // Port icon
                Circle()
                    .fill(portColor(for: port))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: port.dtype.iconName)
                            .font(.system(size: 8))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(port.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(node.kind.displayName) • \(port.dtype.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func portColor(for port: PortDef) -> Color {
        switch port.dtype {
        case .string: return .green
        case .image: return .blue
        case .video: return .purple
        case .json: return .orange
        case .number: return .red
        case .bool: return .yellow
        }
    }
}

// MARK: - Preview

#Preview {
    let sourcePort = PortDef(name: "text_output", dtype: .string, direction: "out")
    let sourceNode = Node.textPrompt(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
    let targetNode = Node.imageGeneration(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
    let targetPort = PortDef(name: "prompt", dtype: .string, direction: "in")
    
    return PortSelectionModal(
        sourcePort: sourcePort,
        sourceNode: sourceNode,
        availableInputPorts: [(targetNode, targetPort)],
        onCancel: {},
        onSelect: { _, _ in }
    )
}
