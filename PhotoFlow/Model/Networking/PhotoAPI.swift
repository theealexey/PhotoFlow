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
        endpoint: String = "https://dummyjson.com/users?limit=30&select=id,firstName,lastName,image"
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
                    DummyUsersResponseDTO.self,
                    from: data
                )

                let photos = response.users.map { user in
                    user.makePhoto()
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

private struct DummyUsersResponseDTO: Decodable {
    let users: [DummyUserDTO]
}

private struct DummyUserDTO: Decodable {

    let id: Int
    let firstName: String
    let lastName: String
    let image: URL

    func makePhoto() -> Photo {
        Photo(
            id: String(id),
            author: "\(firstName) \(lastName)",
            imageURL: image
        )
    }
}
