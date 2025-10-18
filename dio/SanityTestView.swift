import SwiftUI

// MARK: - Sanity Test View
struct SanityTestView: View {
    @State private var counter: Int = 0
    @State private var message: String = "Hello, World!"
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🧪 Sanity Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text(message)
                .font(.title2)
                .foregroundColor(.blue)
            
            HStack(spacing: 20) {
                Button("Increment") {
                    counter += 1
                    message = "Counter: \(counter)"
                }
                .buttonStyle(.borderedProminent)
                
                Button("Reset") {
                    counter = 0
                    message = "Hello, World!"
                }
                .buttonStyle(.bordered)
            }
            
            if counter > 0 {
                Text("✅ SwiftUI is working!")
                    .font(.headline)
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            print("🧪 SanityTestView appeared successfully")
        }
    }
}

// MARK: - Preview
#Preview {
    SanityTestView()
}