// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CopilotCredits",
    platforms: [.macOS(.v13)], // MenuBarExtra + Swift Charts + SMAppService
    targets: [
        // Pure logic (parsing, computations, history): testable without network or UI.
        .target(
            name: "CopilotCreditsCore",
            path: "Sources/CopilotCreditsCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The app: networking, Keychain, SwiftUI.
        .executableTarget(
            name: "CopilotCredits",
            dependencies: ["CopilotCreditsCore"],
            path: "Sources/CopilotCredits"
        ),
        // Tests written from Tests/SPEC.md only (Swift Testing).
        .testTarget(
            name: "CopilotCreditsCoreTests",
            dependencies: ["CopilotCreditsCore"],
            path: "Tests/CopilotCreditsCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
