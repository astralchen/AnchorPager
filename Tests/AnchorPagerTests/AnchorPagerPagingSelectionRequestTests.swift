import Foundation
import XCTest
@testable import AnchorPager

final class AnchorPagerPagingSelectionRequestTests: XCTestCase {
    func testInteractiveTransactionFinishesWithSemanticTerminalOnly() {
        let adapter = NSObject()
        let request = makeRequest(identifier: 1, targetIndex: 2, animated: true, source: .interactive)
        var transaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: 1,
            adapterIdentifier: ObjectIdentifier(adapter)
        )

        XCTAssertFalse(transaction.isReadyToFinish)
        XCTAssertTrue(transaction.recordSemanticTerminal(
            .selected(index: 2),
            requestIdentifier: 1,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))

        XCTAssertTrue(transaction.isReadyToFinish)
        XCTAssertFalse(transaction.didAcknowledgeCompletion)
        XCTAssertFalse(transaction.didAcknowledgeExecutorReady)
    }

    func testNonanimatedExplicitCompletionAcknowledgesCompletionAndExecutorReadyTogether() {
        let adapter = NSObject()
        let request = makeRequest(identifier: 2, targetIndex: 1, animated: false, source: .api)
        var transaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: 0,
            adapterIdentifier: ObjectIdentifier(adapter)
        )

        XCTAssertTrue(transaction.recordSemanticTerminal(
            .selected(index: 1),
            requestIdentifier: 2,
            targetIndex: 1,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))
        XCTAssertFalse(transaction.isReadyToFinish)

        XCTAssertTrue(transaction.acknowledgeProgrammaticCompletion(
            requestIdentifier: 2,
            targetIndex: 1,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))

        XCTAssertTrue(transaction.didAcknowledgeCompletion)
        XCTAssertTrue(transaction.didAcknowledgeExecutorReady)
        XCTAssertTrue(transaction.isReadyToFinish)
    }

    func testAnimatedExplicitTransactionRequiresSemanticCompletionAndExecutorReady() {
        let adapter = NSObject()
        let request = makeRequest(identifier: 3, targetIndex: 2, animated: true, source: .bar)
        var transaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: 0,
            adapterIdentifier: ObjectIdentifier(adapter)
        )

        XCTAssertTrue(transaction.recordSemanticTerminal(
            .selected(index: 2),
            requestIdentifier: 3,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))
        XCTAssertTrue(transaction.acknowledgeProgrammaticCompletion(
            requestIdentifier: 3,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))
        XCTAssertFalse(transaction.didAcknowledgeExecutorReady)
        XCTAssertFalse(transaction.isReadyToFinish)

        XCTAssertTrue(transaction.acknowledgeExecutorReady(
            requestIdentifier: 3,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))

        XCTAssertTrue(transaction.isReadyToFinish)
    }

    func testStaleIdentifierTargetAndAdapterAcknowledgementsDoNotMutateTransaction() {
        let adapter = NSObject()
        let staleAdapter = NSObject()
        let request = makeRequest(identifier: 4, targetIndex: 2, animated: true, source: .api)
        var transaction = AnchorPagerPagingSelectionTransaction(
            request: request,
            previousIndex: 0,
            adapterIdentifier: ObjectIdentifier(adapter)
        )
        let initialTransaction = transaction

        XCTAssertFalse(transaction.recordSemanticTerminal(
            .selected(index: 2),
            requestIdentifier: 99,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))
        XCTAssertFalse(transaction.acknowledgeProgrammaticCompletion(
            requestIdentifier: 4,
            targetIndex: 1,
            adapterIdentifier: ObjectIdentifier(adapter)
        ))
        XCTAssertFalse(transaction.acknowledgeExecutorReady(
            requestIdentifier: 4,
            targetIndex: 2,
            adapterIdentifier: ObjectIdentifier(staleAdapter)
        ))

        XCTAssertEqual(transaction, initialTransaction)
    }

    func testExplicitAdmissionDistinguishesDuplicateFromLatestReplacement() {
        let active = makeRequest(identifier: 5, targetIndex: 1, animated: true, source: .api)
        let pending = makeRequest(identifier: 6, targetIndex: 2, animated: true, source: .bar)
        let duplicate = makeRequest(identifier: 7, targetIndex: 1, animated: false, source: .api)

        XCTAssertEqual(
            AnchorPagerPagingExplicitSelectionAdmission.resolve(
                request: duplicate,
                committedIndex: 0,
                activeRequest: active,
                pendingRequest: nil
            ),
            .duplicate
        )
        XCTAssertEqual(
            AnchorPagerPagingExplicitSelectionAdmission.resolve(
                request: duplicate,
                committedIndex: 0,
                activeRequest: active,
                pendingRequest: pending
            ),
            .replaceLatest
        )
    }

    func testExplicitAdmissionStartsNoOpsAndRejectsInteractiveSource() {
        XCTAssertEqual(
            AnchorPagerPagingExplicitSelectionAdmission.resolve(
                request: makeRequest(identifier: 8, targetIndex: 1, animated: true, source: .api),
                committedIndex: 0,
                activeRequest: nil,
                pendingRequest: nil
            ),
            .start
        )
        XCTAssertEqual(
            AnchorPagerPagingExplicitSelectionAdmission.resolve(
                request: makeRequest(identifier: 9, targetIndex: 0, animated: true, source: .bar),
                committedIndex: 0,
                activeRequest: nil,
                pendingRequest: nil
            ),
            .noOp
        )
        XCTAssertEqual(
            AnchorPagerPagingExplicitSelectionAdmission.resolve(
                request: makeRequest(identifier: 10, targetIndex: 1, animated: true, source: .interactive),
                committedIndex: 0,
                activeRequest: nil,
                pendingRequest: nil
            ),
            .rejectedInteractive
        )
    }

    private func makeRequest(
        identifier: Int,
        targetIndex: Int,
        animated: Bool,
        source: AnchorPagerPagingSelectionSource
    ) -> AnchorPagerPagingSelectionRequest {
        AnchorPagerPagingSelectionRequest(
            identifier: identifier,
            targetIndex: targetIndex,
            animated: animated,
            source: source
        )
    }
}
