import Tabman

@MainActor
enum AnchorPagerTabBarAdapter {
    static func makeDefaultBar() -> TMBar {
        TMBarView.ButtonBar().systemBar()
    }
}
