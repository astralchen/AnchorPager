import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeExampleRootViewController()
        self.window = window
        window.makeKeyAndVisible()
    }
}

@MainActor
func makeExampleRootViewController() -> UITabBarController {
    let pagerViewController = ExamplePagerViewController()
    let navigationController = UINavigationController(rootViewController: pagerViewController)
    navigationController.tabBarItem = UITabBarItem(
        title: "AnchorPager",
        image: UIImage(systemName: "doc.on.doc"),
        selectedImage: UIImage(systemName: "doc.on.doc.fill")
    )

    let tabBarController = UITabBarController()
    tabBarController.viewControllers = [navigationController]
    return tabBarController
}
