# Agent Guidelines for Dio Project

This document contains important guidelines and common issues that AI agents should be aware of when working on this SwiftUI project.

## SwiftUI Common Issues

### ❌ CRITICAL: Print Statements in View Bodies

**Problem**: The error `'buildExpression' is unavailable: this expression does not conform to 'View'` occurs when `print` statements are placed directly inside SwiftUI view bodies.

**What NOT to do**:
```swift
var body: some View {
    print("Debug message") // ❌ This will cause compilation error
    return VStack {
        Text("Hello")
    }
}
```

**What TO do**:
```swift
var body: some View {
    VStack {
        Text("Hello")
    }
    .onAppear {
        print("Debug message") // ✅ This is fine
    }
}
```

**Safe locations for print statements**:
- Inside computed properties (but not the `body` property)
- Inside function bodies
- Inside modifiers like `.onAppear`, `.onChange`, etc.
- Inside action closures (Button actions, etc.)

**Files that have had this issue**:
- `dio/OutputPreviewView.swift` - Had print statements directly in `body` computed property
- `dio/ContentView.swift` - Had print statement directly in `fullScreenCover` modifier

### SwiftUI View Body Rules

The `body` computed property in SwiftUI views must only contain expressions that conform to the `View` protocol. Common violations include:

- `print()` statements
- Variable assignments
- Control flow statements without proper View wrapping
- Direct function calls that don't return Views

## Project Structure

- Main app files are in `dio/` directory
- Test files are in `dioTests/` and `dioUITests/`
- This is a SwiftUI app with a node-based graph interface
- Uses `@StateObject` for shared instances like `ExecutionEngine` and `RunPersistence`

## Common Patterns

- Use `@StateObject` for shared singletons
- Use `@State` for local view state
- Use `@Binding` for two-way data flow
- Prefer `Group` over `AnyView` when possible for better performance

## Debugging Tips

- Use `.onAppear` for debug prints instead of direct print statements in view bodies
- Use Xcode's preview system for rapid iteration
- Check console output for execution flow debugging
- Use proper SwiftUI lifecycle methods for state management

## Building for Device

When building the app, use this command:

```bash
cd /Users/varicklim/dev/dio && xcodebuild -project dio.xcodeproj -scheme dio -destination "platform=iOS,id=00008110-00190DE03A0A401E" build
```

Device details:
- Platform: iOS
- Architecture: arm64
- Device ID: 00008110-00190DE03A0A401E
- Name: Varick's iPhone

---

*Last updated: When this issue was fixed in OutputPreviewView.swift and ContentView.swift on 27 September 2025*
