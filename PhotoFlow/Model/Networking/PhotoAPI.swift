import Foundation

protocol PhotoFetching {

    @discardableResult
    func fetchPhotos(
        completion: @escaping @Sendable (
            Result<[Photo], PhotoFetchError>
        ) -> Void
    ) -> URLSessionDataTask?
}

enum PhotoFetchError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case missingData
    case decodingFailed
    case network
    case cancelled
}

final class PhotoAPI: PhotoFetching {

    private let session: URLSession
    private let endpoint: String

    init(
        session: URLSession = .shared,
        endpoint: String = "https://randomuser.me/api/1.4/?results=30&inc=name,login,picture"
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    @discardableResult
    func fetchPhotos(
        completion: @escaping @Sendable (
            Result<[Photo], PhotoFetchError>
        ) -> Void
    ) -> URLSessionDataTask? {
        guard let url = URL(
            string: endpoint
        ) else {
            completion(
                .failure(.invalidURL)
            )

            return nil
        }

        let task = session.dataTask(
            with: url
        ) { data, response, error in
            if let urlError = error as? URLError {
                if urlError.code == .cancelled {
                    completion(
                        .failure(.cancelled)
                    )

                    return
                }

                completion(
                    .failure(.network)
                )

                return
            }

            if error != nil {
                completion(
                    .failure(.network)
                )

                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                completion(
                    .failure(.invalidResponse)
                )

                return
            }

            guard let data else {
                completion(
                    .failure(.missingData)
                )

                return
            }

            do {
                let decoder = JSONDecoder()

                let response = try decoder.decode(
                    RandomUserResponseDTO.self,
                    from: data
                )

                let photos = response.results.map { dto in
                    dto.makePhoto()
                }

                completion(
                    .success(photos)
                )
            } catch {
                completion(
                    .failure(.decodingFailed)
                )
            }
        }

        task.resume()

        return task
    }
}

private struct RandomUserResponseDTO: Decodable {
    let results: [RandomUserDTO]
}

private struct RandomUserDTO: Decodable {

    let name: NameDTO
    let login: LoginDTO
    let picture: PictureDTO

    func makePhoto() -> Photo {
        Photo(
            id: login.uuid,
            author: "\(name.first) \(name.last)",
            imageURL: picture.large
        )
    }
}

private struct NameDTO: Decodable {
    let first: String
    let last: String
}

private struct LoginDTO: Decodable {
    let uuid: String
}

private struct PictureDTO: Decodable {
    let large: URL
}
