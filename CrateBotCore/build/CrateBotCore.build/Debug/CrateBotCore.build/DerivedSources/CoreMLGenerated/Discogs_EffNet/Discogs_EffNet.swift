//
// Discogs_EffNet.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public class Discogs_EffNetInput : MLFeatureProvider {

    /// input_1 as 1 × 128 × 96 3-dimensional array of 16-bit floats
    public var input_1: MLMultiArray

    public var featureNames: Set<String> { ["input_1"] }

    public func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "input_1" {
            return MLFeatureValue(multiArray: input_1)
        }
        return nil
    }

    public init(input_1: MLMultiArray) {
        self.input_1 = input_1
    }

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    public convenience init(input_1: MLShapedArray<Float16>) {
        self.init(input_1: MLMultiArray(input_1))
    }

}


/// Model Prediction Output Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public class Discogs_EffNetOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// var_1261 as 1 by 400 matrix of 16-bit floats
    public var var_1261: MLMultiArray {
        provider.featureValue(for: "var_1261")!.multiArrayValue!
    }

    /// var_1261 as 1 by 400 matrix of 16-bit floats
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    public var var_1261ShapedArray: MLShapedArray<Float16> {
        MLShapedArray<Float16>(var_1261)
    }

    /// input_295 as 1 by 1280 matrix of 16-bit floats
    public var input_295: MLMultiArray {
        provider.featureValue(for: "input_295")!.multiArrayValue!
    }

    /// input_295 as 1 by 1280 matrix of 16-bit floats
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    public var input_295ShapedArray: MLShapedArray<Float16> {
        MLShapedArray<Float16>(input_295)
    }

    public var featureNames: Set<String> {
        provider.featureNames
    }

    public func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    public init(var_1261: MLMultiArray, input_295: MLMultiArray) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["var_1261" : MLFeatureValue(multiArray: var_1261), "input_295" : MLFeatureValue(multiArray: input_295)])
    }

    public init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
public class Discogs_EffNet {
    public let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle.module
        return bundle.url(forResource: "Discogs_EffNet", withExtension:"mlmodelc")!
    }

    /**
        Construct Discogs_EffNet instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of Discogs_EffNet.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `Discogs_EffNet.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    public convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct Discogs_EffNet instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    public convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    public convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct Discogs_EffNet instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    public class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<Discogs_EffNet, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct Discogs_EffNet instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    public class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> Discogs_EffNet {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct Discogs_EffNet instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    public class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<Discogs_EffNet, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(Discogs_EffNet(model: model)))
            }
        }
    }

    /**
        Construct Discogs_EffNet instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    public class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> Discogs_EffNet {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return Discogs_EffNet(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as Discogs_EffNetInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as Discogs_EffNetOutput
    */
    public func prediction(input: Discogs_EffNetInput) throws -> Discogs_EffNetOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as Discogs_EffNetInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as Discogs_EffNetOutput
    */
    public func prediction(input: Discogs_EffNetInput, options: MLPredictionOptions) throws -> Discogs_EffNetOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return Discogs_EffNetOutput(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as Discogs_EffNetInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as Discogs_EffNetOutput
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    public func prediction(input: Discogs_EffNetInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> Discogs_EffNetOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return Discogs_EffNetOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - input_1: 1 × 128 × 96 3-dimensional array of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as Discogs_EffNetOutput
    */
    public func prediction(input_1: MLMultiArray) throws -> Discogs_EffNetOutput {
        let input_ = Discogs_EffNetInput(input_1: input_1)
        return try prediction(input: input_)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - input_1: 1 × 128 × 96 3-dimensional array of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as Discogs_EffNetOutput
    */

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    public func prediction(input_1: MLShapedArray<Float16>) throws -> Discogs_EffNetOutput {
        let input_ = Discogs_EffNetInput(input_1: input_1)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [Discogs_EffNetInput]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [Discogs_EffNetOutput]
    */
    public func predictions(inputs: [Discogs_EffNetInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [Discogs_EffNetOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [Discogs_EffNetOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  Discogs_EffNetOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
