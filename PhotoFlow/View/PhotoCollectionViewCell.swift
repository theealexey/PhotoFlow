import UIKit

final class PhotoCollectionViewCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoCollectionViewCell"

    private let photoImageView = UIImageView()
    private let authorLabel = UILabel()
    private var representedPhotoID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)

        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        representedPhotoID = nil
        photoImageView.image = nil
        authorLabel.text = nil
    }

    func configure(
        photoID: String,
        author: String
    ) {
        representedPhotoID = photoID
        authorLabel.text = author
    }
    
    func setImage(
        _ image: UIImage,
        for photoID: String
    ) {
        guard representedPhotoID == photoID else {
            return
        }

        photoImageView.image = image
    }

    private func configureView() {
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = 12
        contentView.clipsToBounds = true

        photoImageView.backgroundColor = .tertiarySystemFill
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        photoImageView.translatesAutoresizingMaskIntoConstraints = false

        authorLabel.font = .preferredFont(forTextStyle: .subheadline)
        authorLabel.textColor = .label
        authorLabel.numberOfLines = 1
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(photoImageView)
        contentView.addSubview(authorLabel)

        NSLayoutConstraint.activate([
            photoImageView.topAnchor.constraint(
                equalTo: contentView.topAnchor
            ),
            photoImageView.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor
            ),
            photoImageView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor
            ),
            photoImageView.heightAnchor.constraint(
                equalTo: photoImageView.widthAnchor
            ),

            authorLabel.topAnchor.constraint(
                equalTo: photoImageView.bottomAnchor,
                constant: 8
            ),
            authorLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 10
            ),
            authorLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -10
            ),
            authorLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor,
                constant: -8
            )
        ]
        )
    }
}
