import UIKit

final class PhotoDetailView: UIView {

    let imageView = UIImageView()
    let authorLabel = UILabel()
    let processButton = UIButton(type: .system)

    override init(
        frame: CGRect
    ) {
        super.init(
            frame: frame
        )

        setupView()
        setupImageView()
        setupAuthorLabel()
        setupProcessButton()
        setupHierarchy()
        setupConstraints()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    private func setupView() {
        backgroundColor = .systemBackground
    }

    private func setupImageView() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
    }

    private func setupAuthorLabel() {
        authorLabel.translatesAutoresizingMaskIntoConstraints = false

        authorLabel.font = .preferredFont(
            forTextStyle: .headline
        )

        authorLabel.textAlignment = .center
        authorLabel.numberOfLines = 0
    }

    private func setupProcessButton() {
        processButton.translatesAutoresizingMaskIntoConstraints = false

        processButton.configuration = .filled()

        processButton.configuration?.title = "Process Image"

        processButton.isEnabled = false
    }

    private func setupHierarchy() {
        addSubview(
            imageView
        )

        addSubview(
            authorLabel
        )

        addSubview(
            processButton
        )
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate(
            [
                imageView.topAnchor.constraint(
                    equalTo: safeAreaLayoutGuide.topAnchor,
                    constant: 24
                ),

                imageView.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: 16
                ),

                imageView.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -16
                ),

                imageView.heightAnchor.constraint(
                    equalTo: imageView.widthAnchor
                ),

                authorLabel.topAnchor.constraint(
                    equalTo: imageView.bottomAnchor,
                    constant: 20
                ),

                authorLabel.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: 16
                ),

                authorLabel.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -16
                ),

                processButton.topAnchor.constraint(
                    equalTo: authorLabel.bottomAnchor,
                    constant: 20
                ),

                processButton.centerXAnchor.constraint(
                    equalTo: centerXAnchor
                )
            ]
        )
    }
}
