import Foundation

enum ImageDataLoadError: Error, Equatable, Sendable {
    case invalidResponse
    case missingData
    case network
}

final class ImageDataLoader: Sendable {

    private let session: URLSession
    private let memoryCache: ImageDataMemoryCache
    private let diskCache: DiskImageCache?

    init(
        session: URLSession = .shared,
        memoryCache: ImageDataMemoryCache = ImageDataMemoryCache(),
        diskCache: DiskImageCache? = nil
    ) {
        self.session = session
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    func loadData(
        from url: URL,
        completion: @escaping @Sendable (
            Result<Data, ImageDataLoadError>
        ) -> Void
    ) -> ImageDataLoadRequest {
        let request = ImageDataLoadRequest()

        if let data = memoryCache.data(
            for: url
        ) {
            completion(
                .success(data)
            )

            return request
        }

        guard let diskCache else {
            Self.startNetworkLoad(
                from: url,
                session: session,
                memoryCache: memoryCache,
                diskCache: nil,
                request: request,
                completion: completion
            )

            return request
        }

        diskCache.data(
            for: url
        ) { [session, memoryCache] data in
            guard !request.isCancelled else {
                return
            }

            if let data {
                memoryCache.insert(
                    data,
                    for: url
                )

                completion(
                    .success(data)
                )

                return
            }

            Self.startNetworkLoad(
                from: url,
                session: session,
                memoryCache: memoryCache,
                diskCache: diskCache,
                request: request,
                completion: completion
            )
        }

        return request
    }

    private static func startNetworkLoad(
        from url: URL,
        session: URLSession,
        memoryCache: ImageDataMemoryCache,
        diskCache: DiskImageCache?,
        request: ImageDataLoadRequest,
        completion: @escaping @Sendable (
            Result<Data, ImageDataLoadError>
        ) -> Void
    ) {
        guard !request.isCancelled else {
            return
        }

        let networkTask = session.dataTask(
            with: url
        ) { data, response, error in
            guard !request.isCancelled else {
                return
            }

            if let error {
                if let urlError = error as? URLError,
                   urlError.code == .cancelled {
                    return
                }

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

            guard !request.isCancelled else {
                return
            }

            memoryCache.insert(
                data,
                for: url
            )

            diskCache?.insert(
                data,
                for: url
            )

            completion(
                .success(data)
            )
        }

        request.register(
            networkTask: networkTask
        )

        networkTask.resume()
    }
    
    func removeData(for url: URL) {
        memoryCache.removeData(
            for: url
        )

        diskCache?.removeData(
            for: url
        )
    }
}
