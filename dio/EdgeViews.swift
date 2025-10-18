import SwiftUI

// MARK: - Edge Visual Components

// EdgeView for Graph (Node)
struct EdgeView: View {
    let edge: Edge
    let sourceNode: Node
    let targetNode: Node
    let sourceScreenPosition: CGPoint
    let targetScreenPosition: CGPoint
    let nodeSizes: [UUID: CGSize]
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var showTooltip: Bool = false
    
    var body: some View {
        ZStack {
            // Make edge much more visible for debugging
            edgePath
                .stroke(edgeColor, style: StrokeStyle(lineWidth: isSelected ? 4 : 2, lineCap: .round))
                .contentShape(edgePath.strokedPath(StrokeStyle(lineWidth: 24, lineCap: .round)))
                .onTapGesture {
                    onSelect()
                }
            
            // Tooltip for selected edge
            if isSelected && showTooltip {
                edgeTooltip
            }
        }
        .onAppear {
            if isSelected {
                showTooltip = true
            }
        }
        .onChange(of: isSelected) { oldValue, newValue in
            if newValue {
                showTooltip = true
            } else {
                showTooltip = false
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var edgeColor: Color {
        if isSelected {
            return .blue
        } else {
            return .secondary
        }
    }
    
    private var sourcePosition: CGPoint {
        let sourceNodeSize = nodeSizes[sourceNode.id] ?? CGSize(width: 240, height: 240)
        return CGPoint(
            x: sourceScreenPosition.x,
            y: sourceScreenPosition.y + sourceNodeSize.height / 2
        )
    }
    
    private var targetPosition: CGPoint {
        let targetNodeSize = nodeSizes[targetNode.id] ?? CGSize(width: 240, height: 240)
        return CGPoint(
            x: targetScreenPosition.x,
            y: targetScreenPosition.y - targetNodeSize.height / 2
        )
    }
    
    private var edgeMidpoint: CGPoint {
        CGPoint(
            x: (sourcePosition.x + targetPosition.x) / 2,
            y: (sourcePosition.y + targetPosition.y) / 2
        )
    }
    
    private var edgeTooltip: some View {
        VStack(spacing: 8) {
            Button(action: onDelete) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.caption)
                    Text("Delete")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
            }
        }
        .position(edgeMidpoint)
        .zIndex(1000) // Ensure tooltip appears above everything
    }
    
    private var edgePath: Path {
        Path { path in
            path.move(to: sourcePosition)
            
            // Create a curved path between nodes with vertical start/end
            let controlPoint1 = CGPoint(
                x: sourcePosition.x,
                y: sourcePosition.y + (targetPosition.y - sourcePosition.y) * 0.3
            )
            let controlPoint2 = CGPoint(
                x: targetPosition.x,
                y: targetPosition.y - (targetPosition.y - sourcePosition.y) * 0.3
            )
            
            path.addCurve(to: targetPosition, control1: controlPoint1, control2: controlPoint2)
        }
    }
    
    
}
