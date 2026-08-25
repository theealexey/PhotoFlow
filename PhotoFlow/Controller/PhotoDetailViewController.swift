import UIKit

final class PhotoDetailViewController: UIViewController {
    
    private let contentView = PhotoDetailView()
    
    private let photo: Photo
    private let imageLoader: any ImageLoading
    private let imageProcessor: PhotoImageProcessor
    
    private var imageRequest: ImageLoadRequest?
    private var processingRequest: ImageProcessingRequest?
    
    private var originalImage: UIImage?
    
    init(
        photo: Photo,
        imageLoader: any ImageLoading,
        imageProcessor: PhotoImageProcessor
    ) {
        self.photo = photo
        self.imageLoader = imageLoader
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
        
        title = "Photo"
        
        contentView.authorLabel.text = photo.author
        
        contentView.processButton.addTarget(
            self,
            action: #selector(processImageButtonTapped),
            for: .touchUpInside
        )
        
        loadImage()
    }
    
    private func loadImage() {
        imageRequest?.cancel()
        
        contentView.processButton.isEnabled = false
        
        imageRequest = imageLoader.loadImage(
            from: photo.imageURL
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                
                self.imageRequest = nil
                
                switch result {
                case .success(let image):
                    self.originalImage = image
                    self.contentView.imageView.image = image
                    self.contentView.processButton.isEnabled = true
                    
                case .failure:
                    self.showLoadingError()
                }
            }
        }
    }
    
    @objc
    private func processImageButtonTapped() {
        guard let originalImage else {
            return
        }

        processingRequest?.cancel()

        contentView.processButton.isEnabled = false

        processingRequest = imageProcessor.process(
            image: originalImage
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.processingRequest = nil
                self.contentView.processButton.isEnabled = true

                switch result {
                case .success(let image):
                    self.contentView.imageView.image = image

                case .failure:
                    self.showProcessingError()
                }
            }
        }
    }
    
    override func viewDidDisappear(
        _ animated: Bool
    ) {
        super.viewDidDisappear(
            animated
        )

        guard isMovingFromParent else {
            return
        }

        imageRequest?.cancel()
        imageRequest = nil

        processingRequest?.cancel()
        processingRequest = nil
    }
    private func showLoadingError() {
        let alertController = UIAlertController(
            title: "Unable to Load Photo",
            message: "Please try again.",
            preferredStyle: .alert
        )

        let retryAction = UIAlertAction(
            title: "Retry",
            style: .default
        ) { [weak self] _ in
            self?.loadImage()
        }

        alertController.addAction(
            retryAction
        )

        present(
            alertController,
            animated: true
        )
    }

    private func showProcessingError() {
        let alertController = UIAlertController(
            title: "Unable to Process Photo",
            message: "Please try again.",
            preferredStyle: .alert
        )

        alertController.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )

        present(
            alertController,
            animated: true
        )
    }
}
