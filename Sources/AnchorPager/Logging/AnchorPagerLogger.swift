import OSLog

@MainActor
enum AnchorPagerLogger {
    static let subsystem = "com.anchorpager.AnchorPager"

    static var sink: ((Event) -> Void)?

    enum Category: String, CaseIterable, Sendable {
        case lifecycle
        case layout
        case header
        case paging
        case children
        case scroll
        case inset
        case overscroll
        case gesture
        case accessibility
        case resource
    }

    enum Level: String, Sendable {
        case debug
        case info
        case error
    }

    struct Event: Equatable, Sendable {
        let category: Category
        let level: Level
        let event: String
    }

    static func log(_ level: Level, category: Category, event: String) {
        let record = Event(category: category, level: level, event: event)
        sink?(record)

        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(event, privacy: .public)")
        case .info:
            logger.info("\(event, privacy: .public)")
        case .error:
            logger.error("\(event, privacy: .public)")
        }
    }
}
