import SwiftUI

// MARK: - Grid Background Component

// Lightweight dotted grid background
struct GridBackground: View {
    let canvasSize: CGSize
    
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 24
            let dotSize: CGFloat = 3
            
            // Use the provided canvasSize instead of the view's size
            for x in stride(from: 0, through: canvasSize.width, by: step) {
                for y in stride(from: 0, through: canvasSize.height, by: step) {
                    let dotRect = CGRect(
                        x: x - dotSize/2,
                        y: y - dotSize/2,
                        width: dotSize,
                        height: dotSize
                    )
                    ctx.fill(
                        Path(ellipseIn: dotRect),
                        with: .color(.secondary.opacity(0.2))
                    )
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .background(Color(.systemGroupedBackground))
    }
}
