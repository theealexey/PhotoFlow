import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let photoAPI = PhotoAPI()

        let diskCache = try? DiskImageCache()

        let imageLoader = ImageLoader(
            diskCache: diskCache
        )

        let viewController = PhotoListViewController(
            photoFetcher: photoAPI,
            imageLoader: imageLoader
        )

        let navigationController = UINavigationController(
            rootViewController: viewController
        )

        let window = UIWindow(
            windowScene: windowScene
        )

        window.rootViewController = navigationController

        self.window = window

        window.makeKeyAndVisible()
    }
}
