import XCTest

final class AnchorPagerSwiftToolchainBaselineTests: XCTestCase {
    func testPackageRequiresSwift62AndKeepsSwift6LanguageMode() throws {
        let manifest = try String(contentsOf: packageRoot().appendingPathComponent("Package.swift"))
        XCTAssertTrue(manifest.hasPrefix("// swift-tools-version: 6.2"))
        XCTAssertTrue(manifest.contains("swiftLanguageModes: [.v6]"))
    }

    func testPagerKeepsVerifiedSynchronousMainActorDeinit() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/AnchorPager/Public/AnchorPagerViewController.swift")
        )
        XCTAssertTrue(source.contains("MainActor.assumeIsolated"))
        XCTAssertFalse(source.contains("isolated deinit"))
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("Package.swift").path
            ) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
