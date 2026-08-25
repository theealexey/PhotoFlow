import Foundation
import Synchronization
import Testing

@testable import PhotoFlow

@Suite(.serialized)
struct PhotoAPITests {

    @Test
    func successfulResponseMapsDTOsToPhotos() async {
        let json = """
        {
            "results": [
                {
                    "name": {
                        "first": "Ada",
                        "last": "Lovelace"
                    },
                    "login": {
                        "uuid": "user-1"
                    },
                    "picture": {
                        "large": "https://example.com/ada.jpg"
                    }
                },
                {
                    "name": {
                        "first": "Alan",
                        "last": "Turing"
                    },
                    "login": {
                        "uuid": "user-2"
                    },
                    "picture": {
                        "large": "https://example.com/alan.jpg"
                    }
                }
            ]
        }
        """

        let responseData = Data(
            json.utf8
        )

        PhotoAPIURLProtocolStub.prepare(
            statusCode: 200,
            responseData: responseData
        )

        let session = makeStubbedSession()

        let photoAPI = PhotoAPI(
            session: session,
            endpoint: "https://example.com/photos"
        )

        let result = await fetchPhotos(
            using: photoAPI
        )

        guard
            let adaURL = URL(
                string: "https://example.com/ada.jpg"
            ),
            let alanURL = URL(
                string: "https://example.com/alan.jpg"
            )
        else {
            Issue.record(
                "Expected valid test image URLs"
            )

            return
        }

        let expectedPhotos = [
            Photo(
                id: "user-1",
                author: "Ada Lovelace",
                imageURL: adaURL
            ),
            Photo(
                id: "user-2",
                author: "Alan Turing",
                imageURL: alanURL
            )
        ]

        switch result {
        case .success(let photos):
            #expect(
                photos == expectedPhotos
            )

        case .failure(let error):
            Issue.record(
                "Expected successful response, received \(error)"
            )
        }
    }

    @Test
    func unsuccessfulHTTPStatusReturnsInvalidResponse() async {
        PhotoAPIURLProtocolStub.prepare(
            statusCode: 500,
            responseData: Data()
        )

        let session = makeStubbedSession()

        let photoAPI = PhotoAPI(
            session: session,
            endpoint: "https://example.com/photos"
        )

        let result = await fetchPhotos(
            using: photoAPI
        )

        #expect(
            result == .failure(.invalidResponse)
        )
    }

    @Test
    func malformedJSONReturnsDecodingFailed() async {
        let responseData = Data(
            "not valid json".utf8
        )

        PhotoAPIURLProtocolStub.prepare(
            statusCode: 200,
            responseData: responseData
        )

        let session = makeStubbedSession()

        let photoAPI = PhotoAPI(
            session: session,
            endpoint: "https://example.com/photos"
        )

        let result = await fetchPhotos(
            using: photoAPI
        )

        #expect(
            result == .failure(.decodingFailed)
        )
    }

    @Test
    func networkErrorReturnsNetworkError() async {
        PhotoAPIURLProtocolStub.prepare(
            error: URLError(
                .notConnectedToInternet
            )
        )

        let session = makeStubbedSession()

        let photoAPI = PhotoAPI(
            session: session,
            endpoint: "https://example.com/photos"
        )

        let result = await fetchPhotos(
            using: photoAPI
        )

        #expect(
            result == .failure(.network)
        )
    }

    @Test
    func cancelledURLErrorReturnsCancelled() async {
        PhotoAPIURLProtocolStub.prepare(
            error: URLError(
                .cancelled
            )
        )

        let session = makeStubbedSession()

        let photoAPI = PhotoAPI(
            session: session,
            endpoint: "https://example.com/photos"
        )

        let result = await fetchPhotos(
            using: photoAPI
        )

        #expect(
            result == .failure(.cancelled)
        )
    }

    private func fetchPhotos(
        using photoAPI: PhotoAPI
    ) async -> Result<[Photo], PhotoFetchError> {
        var task: URLSessionDataTask?

        let result = await withCheckedContinuation { continuation in
            task = photoAPI.fetchPhotos { result in
                continuation.resume(
                    returning: result
                )
            }
        }

        withExtendedLifetime(task) {}

        return result
    }

    private func makeStubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral

        configuration.protocolClasses = [
            PhotoAPIURLProtocolStub.self
        ]

        return URLSession(
            configuration: configuration
        )
    }
}

private final class PhotoAPIURLProtocolStub: URLProtocol {

    private struct State {
        var statusCode = 200
        var responseData = Data()
        var error: URLError?
    }

    private static let state = Mutex(
        State()
    )

    static func prepare(
        statusCode: Int = 200,
        responseData: Data = Data(),
        error: URLError? = nil
    ) {
        state.withLock { state in
            state.statusCode = statusCode
            state.responseData = responseData
            state.error = error
        }
    }

    override class func canInit(
        with request: URLRequest
    ) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let configuration = Self.state.withLock { state in
            StubConfiguration(
                statusCode: state.statusCode,
                responseData: state.responseData,
                error: state.error
            )
        }

        if let error = configuration.error {
            client?.urlProtocol(
                self,
                didFailWithError: error
            )

            return
        }

        guard let url = request.url else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(
                    .badURL
                )
            )

            return
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: configuration.statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(
                    .badServerResponse
                )
            )

            return
        }

        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )

        client?.urlProtocol(
            self,
            didLoad: configuration.responseData
        )

        client?.urlProtocolDidFinishLoading(
            self
        )
    }

    override func stopLoading() {}
}

private struct StubConfiguration: Sendable {
    let statusCode: Int
    let responseData: Data
    let error: URLError?
}
