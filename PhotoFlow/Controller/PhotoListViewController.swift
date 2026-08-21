import UIKit

final class PhotoListViewController: UIViewController {

    private let contentView = PhotoListView()

    override func loadView() {
        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Photos"
    }
}
