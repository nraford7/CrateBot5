import Foundation
import CoreML
import os.log

/// Manages CoreML model discovery, loading, and validation
public actor ModelManager {
    private let logger = Logger(subsystem: "com.cratebot.core", category: "ModelManager")
    private let fileManager = FileManager.default

    /// Directories to search for models
    private let modelDirectories: [URL]

    /// Currently loaded model name
    private var loadedModelName: String?

    public init(additionalDirectories: [URL] = []) {
        var dirs: [URL] = additionalDirectories

        // App Support models directory
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            dirs.append(appSupport.appendingPathComponent("CrateBot/Models"))
        }

        // Bundle models
        if let bundleModels = Bundle.main.resourceURL?.appendingPathComponent("Models") {
            dirs.append(bundleModels)
        }

        self.modelDirectories = dirs
    }

    public enum ModelError: Error, LocalizedError, Sendable {
        case modelNotFound(String)
        case loadFailed(String)
        case incompatiblePipelineVersion(expected: String, found: String)
        case noModelsAvailable

        public var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "Model not found: \(name)"
            case .loadFailed(let reason):
                return "Failed to load model: \(reason)"
            case .incompatiblePipelineVersion(let expected, let found):
                return "Model pipeline version mismatch: expected \(expected), found \(found)"
            case .noModelsAvailable:
                return "No models available"
            }
        }
    }

    /// List available models
    public func listModels() -> [AvailableModel] {
        var models: [AvailableModel] = []
        let defaultModelName = UserDefaults.standard.string(forKey: "defaultModelName")

        for directory in modelDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }

            for url in contents where url.pathExtension == "mlmodelc" || url.pathExtension == "mlpackage" {
                let name = url.deletingPathExtension().lastPathComponent
                let metadataURL = url.deletingPathExtension().appendingPathExtension("json")
                let metadata = try? ModelMetadata.load(from: metadataURL)

                models.append(AvailableModel(
                    name: name,
                    url: url,
                    metadata: metadata,
                    isDefault: name == defaultModelName
                ))
            }
        }

        return models.sorted { $0.name < $1.name }
    }

    /// Get model by name
    public func getModel(named name: String) -> AvailableModel? {
        listModels().first { $0.name == name }
    }

    /// Set default model
    public func setDefaultModel(name: String) {
        UserDefaults.standard.set(name, forKey: "defaultModelName")
        logger.info("Set default model to: \(name)")
    }

    /// Persist the last loaded model path in Application Support.
    public func saveDefaultModelPath(_ path: String) throws {
        let url = try defaultModelPathURL()
        try path.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Load the last saved model path from Application Support.
    public func loadDefaultModelPath() -> String? {
        guard let url = try? defaultModelPathURL(),
              let path = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Find the most recently modified trained model directory.
    public func latestTrainedModelDirectory() -> URL? {
        guard let modelsDir = try? modelsDirectory(),
              let contents = try? fileManager.contentsOfDirectory(
                at: modelsDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return nil
        }

        let candidateDirs = contents.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                return false
            }
            let modelFiles = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "mlmodel" || $0.pathExtension == "mlmodelc" } ?? []
            return !modelFiles.isEmpty
        }

        return candidateDirs
            .compactMap { url -> (URL, Date)? in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return date.map { (url, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .first?
            .0
    }

    /// Get the models directory (creating if needed)
    public func modelsDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelError.loadFailed("Cannot access Application Support directory")
        }

        let modelsDir = appSupport.appendingPathComponent("CrateBot/Models")

        if !fileManager.fileExists(atPath: modelsDir.path) {
            try fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    /// Copy a model to the models directory
    public func installModel(from sourceURL: URL, metadata: ModelMetadata) throws {
        let modelsDir = try modelsDirectory()
        let destURL = modelsDir.appendingPathComponent(sourceURL.lastPathComponent)

        // Copy model
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destURL)

        // Save metadata
        let metadataURL = destURL.deletingPathExtension().appendingPathExtension("json")
        try metadata.save(to: metadataURL)

        logger.info("Installed model: \(metadata.name)")
    }

    /// Delete a model
    public func deleteModel(named name: String) throws {
        guard let model = getModel(named: name) else {
            throw ModelError.modelNotFound(name)
        }

        try fileManager.removeItem(at: model.url)

        // Also delete metadata if exists
        let metadataURL = model.url.deletingPathExtension().appendingPathExtension("json")
        try? fileManager.removeItem(at: metadataURL)

        logger.info("Deleted model: \(name)")
    }

    private func defaultModelPathURL() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelError.loadFailed("Cannot access Application Support directory")
        }
        let baseDir = appSupport.appendingPathComponent("CrateBot")
        if !fileManager.fileExists(atPath: baseDir.path) {
            try fileManager.createDirectory(at: baseDir, withIntermediateDirectories: true)
        }
        return baseDir.appendingPathComponent("default_model_path.txt")
    }
}
