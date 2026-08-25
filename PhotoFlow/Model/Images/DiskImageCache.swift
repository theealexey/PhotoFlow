import CryptoKit
import Foundation

final class DiskImageCache: Sendable {

    private let directoryURL: URL
    private let diskQueue: DispatchQueue

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) throws {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let cachesDirectory = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            self.directoryURL = cachesDirectory.appendingPathComponent(
                "PhotoFlowImages",
                isDirectory: true
            )
        }

        diskQueue = DispatchQueue(
            label: "com.alexeywestergaard.PhotoFlow.image-disk-cache",
            qos: .utility
        )

        try fileManager.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    func data(
        for url: URL,
        completion: @escaping @Sendable (Data?) -> Void
    ) {
        diskQueue.async { [directoryURL] in
            let fileName = Self.fileName(
                for: url
            )

            let fileURL = directoryURL.appendingPathComponent(
                fileName,
                isDirectory: false
            )

            let data = try? Data(
                contentsOf: fileURL
            )

            completion(
                data
            )
        }
    }

    func insert(
        _ data: Data,
        for url: URL
    ) {
        diskQueue.async { [directoryURL] in
            let fileName = Self.fileName(
                for: url
            )

            let fileURL = directoryURL.appendingPathComponent(
                fileName,
                isDirectory: false
            )

            try? data.write(
                to: fileURL,
                options: .atomic
            )
        }
    }

    func removeData(for url: URL) {
        diskQueue.async { [directoryURL] in
            let fileName = Self.fileName(
                for: url
            )

            let fileURL = directoryURL.appendingPathComponent(
                fileName,
                isDirectory: false
            )

            try? FileManager.default.removeItem(
                at: fileURL
            )
        }
    }
    
    private static func fileName(
        for url: URL
    ) -> String {
        let urlData = Data(
            url.absoluteString.utf8
        )

        let digest = SHA256.hash(
            data: urlData
        )

        return digest.map { byte in
            String(
                format: "%02x",
                byte
            )
        }
        .joined()
    }
}
