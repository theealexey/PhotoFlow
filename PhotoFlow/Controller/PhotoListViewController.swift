import UIKit

final class PhotoListViewController: UIViewController {

    private let contentView = PhotoListView()
    private let photoFetcher: any PhotoFetching
    private let imageLoader: any ImageLoading
    private let imagePrefetcher: ImagePrefetcher
    private let imageProcessor: PhotoImageProcessor

    private var photos: [Photo] = []
    private var fetchTask: URLSessionDataTask?
    private var imageRequests: [String: ActiveImageRequest] = [:]

    private struct ActiveImageRequest {
        let id: UUID
        var request: ImageLoadRequest?
    }

    init(
        photoFetcher: any PhotoFetching,
        imageLoader: any ImageLoading,
        imagePrefetcher: ImagePrefetcher,
        imageProcessor: PhotoImageProcessor
    ) {
        self.photoFetcher = photoFetcher
        self.imageLoader = imageLoader
        self.imagePrefetcher = imagePrefetcher
        self.imageProcessor = imageProcessor

        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        view = contentView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Photos"

        contentView.collectionView.delegate = self
        contentView.collectionView.dataSource = self
        contentView.collectionView.prefetchDataSource = self

        loadPhotos()
    }

    private func loadPhotos() {
        fetchTask?.cancel()

        fetchTask = photoFetcher.fetchPhotos { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.fetchTask = nil

                switch result {
                case .success(let photos):
                    self.photos = photos
                    self.contentView.collectionView.reloadData()

                case .failure(.cancelled):
                    return

                case .failure:
                    self.showLoadingError()
                }
            }
        }
    }

    private func loadImage(for photo: Photo) {
        imageRequests[photo.id]?.request?.cancel()

        let requestID = UUID()

        imageRequests[photo.id] = ActiveImageRequest(
            id: requestID,
            request: nil
        )

        let request = imageLoader.loadImage(
            from: photo.imageURL
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                guard self.imageRequests[photo.id]?.id == requestID else {
                    return
                }

                self.imageRequests[photo.id] = nil

                switch result {
                case .success(let image):
                    self.displayImage(
                        image,
                        for: photo
                    )

                case .failure:
                    return
                }
            }
        }

        guard imageRequests[photo.id]?.id == requestID else {
            request.cancel()
            return
        }

        imageRequests[photo.id]?.request = request
    }

    private func displayImage(
        _ image: UIImage,
        for photo: Photo
    ) {
        guard let item = photos.firstIndex(
            where: { $0.id == photo.id }
        ) else {
            return
        }

        let indexPath = IndexPath(
            item: item,
            section: 0
        )

        guard let cell = contentView.collectionView.cellForItem(
            at: indexPath
        ) as? PhotoCollectionViewCell else {
            return
        }

        cell.setImage(
            image,
            for: photo.id
        )
    }

    private func showLoadingError() {
        let alertController = UIAlertController(
            title: "Unable to Load Photos",
            message: "Please try again.",
            preferredStyle: .alert
        )

        let retryAction = UIAlertAction(
            title: "Retry",
            style: .default
        ) { [weak self] _ in
            self?.loadPhotos()
        }

        alertController.addAction(
            retryAction
        )

        present(
            alertController,
            animated: true
        )
    }
}

extension PhotoListViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let spacing: CGFloat = 12
        let horizontalInsets: CGFloat = 24

        let availableWidth = collectionView.bounds.width
            - horizontalInsets
            - spacing

        let itemWidth = availableWidth / 2

        return CGSize(
            width: itemWidth,
            height: itemWidth + 42
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard photos.indices.contains(indexPath.item) else {
            return
        }

        let photo = photos[indexPath.item]

        imageRequests[photo.id]?.request?.cancel()
        imageRequests[photo.id] = nil
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard photos.indices.contains(indexPath.item) else {
            return
        }

        let photo = photos[indexPath.item]

        let detailViewController = PhotoDetailViewController(
            photo: photo,
            imageLoader: imageLoader,
            imageProcessor: imageProcessor
        )

        navigationController?.pushViewController(
            detailViewController,
            animated: true
        )
    }
}

extension PhotoListViewController: UICollectionViewDataSource {

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        photos.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PhotoCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? PhotoCollectionViewCell else {
            return UICollectionViewCell()
        }

        let photo = photos[indexPath.item]

        cell.configure(
            photoID: photo.id,
            author: photo.author
        )

        loadImage(
            for: photo
        )

        return cell
    }
}

extension PhotoListViewController: UICollectionViewDataSourcePrefetching {

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        let urls = indexPaths.compactMap { indexPath -> URL? in
            guard photos.indices.contains(indexPath.item) else {
                return nil
            }

            return photos[indexPath.item].imageURL
        }

        imagePrefetcher.prefetch(
            urls: urls
        )
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        let urls = indexPaths.compactMap { indexPath -> URL? in
            guard photos.indices.contains(indexPath.item) else {
                return nil
            }

            return photos[indexPath.item].imageURL
        }

        imagePrefetcher.cancelPrefetching(
            urls: urls
        )
    }
}

