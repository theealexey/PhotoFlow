import Foundation
import Synchronization

final class ImageDataLoadRequest: Sendable {

    private let state = ImageDataLoadRequestState()

    func register(
        networkTask: URLSessionDataTask
    ) {
        state.register(
            networkTask: networkTask
        )
    }

    func cancel() {
        state.cancel()
    }

    var isCancelled: Bool {
        state.isCancelled
    }

    deinit {
        cancel()
    }
}

private final class ImageDataLoadRequestState: Sendable {

    private struct State {
        var isCancelled = false
        var networkTask: URLSessionDataTask?
    }

    private let state = Mutex(
        State()
    )

    func register(
        networkTask: URLSessionDataTask
    ) {
        let shouldCancel = state.withLock { state in
            if state.isCancelled {
                return true
            }

            state.networkTask = networkTask

            return false
        }

        if shouldCancel {
            networkTask.cancel()
        }
    }

    func cancel() {
        let networkTask = state.withLock { state in
            state.isCancelled = true

            let networkTask = state.networkTask
            state.networkTask = nil

            return networkTask
        }

        networkTask?.cancel()
    }

    var isCancelled: Bool {
        state.withLock { state in
            state.isCancelled
        }
    }
}
