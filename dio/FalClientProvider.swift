import Foundation
import FalClient

// Global FAL client instance configured once for the app.
// Configure via env var FAL_KEYPAIR (Scheme → Run) or Info.plist key FAL_KEYPAIR.
let fal: any Client = {
    if let envKeypair = ProcessInfo.processInfo.environment["FAL_KEYPAIR"], !envKeypair.isEmpty {
        return FalClient.withCredentials(.keyPair(envKeypair))
    }
    if let plistKeypair = Bundle.main.object(forInfoDictionaryKey: "FAL_KEYPAIR") as? String, !plistKeypair.isEmpty {
        return FalClient.withCredentials(.keyPair(plistKeypair))
    }
    fatalError("FAL credentials missing. Set FAL_KEYPAIR in the Run scheme or Info.plist (format: FAL_KEY_ID:FAL_KEY_SECRET)")
}()
