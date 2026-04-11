import Foundation

/// Configuration options for the training pipeline
public struct TrainingConfiguration: Codable, Sendable, Equatable {
    /// Minimum positive samples required to train a tag classifier
    public var minSamplesPerTag: Int

    /// Maximum negative:positive ratio to prevent class imbalance
    public var maxNegativeRatio: Double

    /// Mixup augmentation alpha parameter (Beta distribution)
    public var mixupAlpha: Float

    /// Ratio of training data to augment with mixup
    public var mixupRatio: Float

    /// Gaussian noise percentage added to features
    public var featureNoisePercent: Float

    /// Fraction of data held out for validation
    public var validationSplit: Double

    /// Whether to apply mixup augmentation
    public var enableMixup: Bool

    /// Whether to add Gaussian noise to extracted features for regularization
    public var enableFeatureNoise: Bool

    /// MLBoostedTreeClassifier max depth
    public var treeMaxDepth: Int

    /// MLBoostedTreeClassifier iterations
    public var treeIterations: Int

    /// MLBoostedTreeClassifier step size (learning rate)
    public var treeStepSize: Double

    /// Whether to enable label smoothing
    public var enableLabelSmoothing: Bool

    /// Label smoothing factor (typically 0.1)
    public var labelSmoothingFactor: Float

    /// Whether to enable contrastive loss diagnostic logging
    public var enableContrastiveLoss: Bool

    /// Random seed for reproducible training
    public var randomSeed: Int

    public init(
        minSamplesPerTag: Int = 50,
        maxNegativeRatio: Double = 1.5,
        mixupAlpha: Float = 0.4,
        mixupRatio: Float = 0.3,
        featureNoisePercent: Float = 0.02,
        validationSplit: Double = 0.2,
        enableMixup: Bool = true,
        enableFeatureNoise: Bool = true,
        treeMaxDepth: Int = 6,
        treeIterations: Int = 100,
        treeStepSize: Double = 0.3,
        enableLabelSmoothing: Bool = true,
        labelSmoothingFactor: Float = 0.1,
        enableContrastiveLoss: Bool = true,
        randomSeed: Int = 42
    ) {
        self.minSamplesPerTag = minSamplesPerTag
        self.maxNegativeRatio = maxNegativeRatio
        self.mixupAlpha = mixupAlpha
        self.mixupRatio = mixupRatio
        self.featureNoisePercent = featureNoisePercent
        self.validationSplit = validationSplit
        self.enableMixup = enableMixup
        self.enableFeatureNoise = enableFeatureNoise
        self.treeMaxDepth = treeMaxDepth
        self.treeIterations = treeIterations
        self.treeStepSize = treeStepSize
        self.enableLabelSmoothing = enableLabelSmoothing
        self.labelSmoothingFactor = labelSmoothingFactor
        self.enableContrastiveLoss = enableContrastiveLoss
        self.randomSeed = randomSeed
    }

    /// Default configuration
    public static let `default` = TrainingConfiguration()
}
