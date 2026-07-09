enum AnchorPagerAssertions {
    @TaskLocal static var isEnabled = true

    static func failure(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        #if DEBUG
        if isEnabled {
            assertionFailure(message(), file: file, line: line)
        }
        #endif
    }
}
