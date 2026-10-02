import Foundation

public struct CoreAIDirectoryModelResourceProvider:
    CoreAIModelResourceProviding,
    Sendable
{
    public let identifier: String
    public let directoryURL: URL?
    public let requiredFileExtension: String?

    public init(
        identifier: String,
        directoryURL: URL?,
        requiredFileExtension: String? = "aimodel"
    ) {
        self.identifier = identifier
        self.directoryURL = directoryURL
        self.requiredFileExtension =
            requiredFileExtension?
            .trimmingCharacters(
                in: CharacterSet(
                    charactersIn: "."
                )
            )
            .lowercased()
    }

    public func modelResource()
        async throws -> CoreAIModelResource?
    {
        guard
            let directoryURL,
            directoryExists(
                directoryURL
            )
        else {
            return nil
        }

        if
            let requiredFileExtension,
            !requiredFileExtension.isEmpty,
            !containsDescendant(
                withExtension:
                    requiredFileExtension,
                under: directoryURL
            )
        {
            return nil
        }

        return CoreAIModelResource(
            identifier: identifier,
            path: directoryURL.path
        )
    }

    private func directoryExists(
        _ url: URL
    ) -> Bool {
        var isDirectory:
            ObjCBool = false

        guard
            FileManager.default
            .fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            )
        else {
            return false
        }

        return isDirectory.boolValue
    }

    private func containsDescendant(
        withExtension fileExtension:
            String,
        under directoryURL: URL
    ) -> Bool {
        guard
            let enumerator =
                FileManager.default
                .enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys:
                        nil,
                    options: [
                        .skipsHiddenFiles
                    ]
                )
        else {
            return false
        }

        for case let url as URL
            in enumerator
        {
            if
                url.pathExtension
                    .lowercased()
                == fileExtension
            {
                return true
            }
        }

        return false
    }
}
