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
        XCTAssertTrue(hasVerifiedSynchronousMainActorDeinit(in: source))
    }

    func testDeinitContractRejectsInvalidSourceShapes() {
        let invalidSources = [
            """
            func cleanup() { MainActor.assumeIsolated {} }
            deinit {
                pageStateStore.releaseAll()
                managedInsetCoordinator.releaseAll()
            }
            """,
            """
            deinit {
                MainActor.assumeIsolated {
                    managedInsetCoordinator.releaseAll()
                }
            }
            """,
            """
            deinit {
                MainActor.assumeIsolated {
                    pageStateStore.releaseAll()
                }
            }
            """,
            """
            deinit {
                MainActor.assumeIsolated {
                    pageStateStore.releaseAll()
                    managedInsetCoordinator.releaseAll()
                }
                Task {}
            }
            """,
            """
            isolated deinit {
                MainActor.assumeIsolated {
                    pageStateStore.releaseAll()
                    managedInsetCoordinator.releaseAll()
                }
            }
            """,
        ]

        for source in invalidSources {
            XCTAssertFalse(hasVerifiedSynchronousMainActorDeinit(in: source))
        }
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

private func hasVerifiedSynchronousMainActorDeinit(in source: String) -> Bool {
    guard !source.contains("isolated deinit"),
          let deinitBlock = ordinaryDeinitBlock(in: source) else {
        return false
    }

    return deinitBlock.contains("MainActor.assumeIsolated") &&
        deinitBlock.contains("pageStateStore.releaseAll()") &&
        deinitBlock.contains("managedInsetCoordinator.releaseAll()") &&
        !deinitBlock.contains("Task")
}

private func ordinaryDeinitBlock(in source: String) -> Substring? {
    guard let signature = source.range(
        of: #"(?m)^[\t ]*deinit[\t ]*\{"#,
        options: .regularExpression
    ),
    let openingBrace = source[signature].firstIndex(of: "{") else {
        return nil
    }

    var depth = 0
    for index in source[openingBrace...].indices {
        switch source[index] {
        case "{":
            depth += 1
        case "}":
            depth -= 1
            if depth == 0 {
                return source[openingBrace...index]
            }
        default:
            break
        }
    }
    return nil
}
