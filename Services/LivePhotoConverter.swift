import Foundation
import AVFoundation
import Photos
import CoreGraphics

/// 转换错误枚举
///
/// 定义视频转 Live Photo 过程中可能出现的所有错误类型。
/// 遵循 `LocalizedError` 协议，提供中文错误描述。
enum ConversionError: Error, LocalizedError {
    /// 相册权限被拒绝
    case permissionDenied
    /// 未找到视频资源（videoURL 为 nil）
    case assetNotFound
    /// 图片生成失败（关键帧提取或 JPEG 写入失败）
    case imageGenerationFailed
    /// 视频处理失败（裁剪或元数据写入失败）
    case videoProcessingFailed
    /// 保存到相册失败
    case saveFailed
    /// 无效的视频格式（时长为零或不可用）
    case invalidVideoFormat
    /// 无法获取视频文件 URL
    case videoURLNotAvailable
    /// 没有待转换的任务
    case noTasksToConvert
    /// 正在转换中，无法启动新转换
    case alreadyConverting

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "相册权限被拒绝，请在设置中允许访问相册"
        case .assetNotFound:
            return "未找到视频资源"
        case .imageGenerationFailed:
            return "图片生成失败"
        case .videoProcessingFailed:
            return "视频处理失败"
        case .saveFailed:
            return "保存到相册失败"
        case .invalidVideoFormat:
            return "无效的视频格式"
        case .videoURLNotAvailable:
            return "无法获取视频文件"
        case .noTasksToConvert:
            return "没有待转换的任务"
        case .alreadyConverting:
            return "正在转换中，请等待当前任务完成"
        }
    }
}

/// Live Photo 核心转换引擎
///
/// 编排视频到 Live Photo 的完整转换流程，是服务层的核心协调器。
///
/// 转换流程：
/// 1. 请求相册写入权限
/// 2. 加载视频资源并获取时长
/// 3. 生成 Live Photo 配对标识符（UUID）
/// 4. 根据设置提取关键帧（封面帧）
/// 5. 将标识符写入 JPEG 图片元数据
/// 6. 处理视频（裁剪 + 写入元数据）
/// 7. 将配对的图片和视频保存为 Live Photo
/// 8. 清理临时文件
///
/// 使用 `TempFileManager` 管理临时文件生命周期，
/// 通过 `progressHandler` 回调实时报告转换进度（0.0 ~ 1.0），
/// 在各步骤间检查 `Task.checkCancellation()` 支持取消操作。
final class LivePhotoConverter {

    /// 共享单例
    static let shared = LivePhotoConverter()

    /// 进度回调类型
    ///
    /// 参数为当前进度值，取值范围 0.0 ~ 1.0。
    /// 注意：回调可能在后台线程执行，如需更新 UI 请自行切换到主线程。
    typealias ProgressHandler = (Double) -> Void

    // MARK: - 依赖服务

    /// 临时文件管理器
    private let tempFileManager = TempFileManager.shared
    /// 视频处理器
    private let videoProcessor = VideoProcessor.shared
    /// 元数据写入器
    private let metadataWriter = MetadataWriter.shared
    /// 相册管理器
    private let photoLibraryManager = PhotoLibraryManager.shared

    /// 私有初始化，确保单例模式
    private init() {}

    // MARK: - 转换流程

    /// 执行完整的视频转 Live Photo 流程（静态入口）
    ///
    /// 供 ViewModel 调用的静态方法，内部委托给单例实例执行。
    ///
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - settings: 转换设置，包含封面帧位置、最大时长、输出质量
    ///   - progressHandler: 进度回调，取值范围 0.0 ~ 1.0
    /// - Throws: 转换过程中出现的 `ConversionError`
    static func convert(
        videoURL: URL,
        settings: LivePhotoSettings,
        progressHandler: @escaping (Double) -> Void
    ) async throws {
        try await shared.performConversion(
            videoURL: videoURL,
            settings: settings,
            progressHandler: progressHandler
        )
    }

    /// 执行完整的视频转 Live Photo 流程（内部实现）
    ///
    /// 完整流程包含以下步骤：
    ///
    /// 1. **权限检查**（0.05）：请求相册写入权限，验证授权状态
    /// 2. **加载视频**（0.10 ~ 0.15）：从 URL 加载 AVAsset，获取视频时长
    /// 3. **生成标识符**：调用 `MetadataWriter.generateIdentifier()` 生成 UUID
    /// 4. **提取关键帧**（0.15 ~ 0.30）：根据 `coverFramePosition` 设置提取封面帧
    /// 5. **写入图片元数据**（0.30 ~ 0.40）：将关键帧写入 JPEG 并附加 Apple Maker Note 元数据
    /// 6. **处理视频**（0.40 ~ 0.80）：
    ///    - 裁剪视频到 `maxVideoDuration`（如需要）
    ///    - 写入 content identifier 和 still-image-time 元数据
    /// 7. **保存 Live Photo**（0.80 ~ 0.95）：将图片和视频配对保存到相册
    /// 8. **清理**（0.95 ~ 1.0）：删除所有临时文件
    ///
    /// - Parameters:
    ///   - videoURL: 视频文件 URL
    ///   - settings: 转换设置，包含封面帧位置、最大时长、输出质量
    ///   - progressHandler: 进度回调，取值范围 0.0 ~ 1.0
    /// - Throws: 转换过程中出现的 `ConversionError`
    private func performConversion(
        videoURL: URL,
        settings: LivePhotoSettings,
        progressHandler: (Double) -> Void
    ) async throws {
        // 临时文件收集，用于最终统一清理
        var tempFiles: [URL] = []

        // 使用 defer 确保无论成功或失败都清理临时文件
        defer {
            tempFileManager.cleanupAll(urls: tempFiles)
        }

        // 提前读取设置值，避免在后台线程访问 @Published 属性
        let coverFramePosition = settings.coverFramePosition
        let maxVideoDuration = settings.maxVideoDuration
        let exportPreset = settings.outputQuality.exportPreset

        // MARK: 1. 检查取消 & 请求相册权限
        try Task.checkCancellation()
        progressHandler(0.05)

        let authStatus = await photoLibraryManager.requestAuthorization()
        guard authStatus == .authorized || authStatus == .limited else {
            throw ConversionError.permissionDenied
        }

        try Task.checkCancellation()
        progressHandler(0.10)

        // MARK: 2. 加载视频资源
        let asset = AVURLAsset(url: videoURL)

        // 获取视频时长
        let videoDuration: Double
        do {
            videoDuration = try await videoProcessor.getVideoDuration(asset: asset)
        } catch {
            throw ConversionError.invalidVideoFormat
        }

        guard videoDuration > 0 else {
            throw ConversionError.invalidVideoFormat
        }

        try Task.checkCancellation()
        progressHandler(0.15)

        // MARK: 3. 生成 Live Photo 配对标识符
        let identifier = MetadataWriter.generateIdentifier()

        // MARK: 4. 提取关键帧（封面帧）
        // 根据 coverFramePosition 设置计算封面帧时间点
        let keyFrameTimeSeconds = coverFramePosition.timestamp(forDuration: videoDuration)
        let keyFrameTime = CMTime(
            seconds: keyFrameTimeSeconds,
            preferredTimescale: 600
        )

        let keyFrameImage: CGImage
        do {
            keyFrameImage = try await videoProcessor.extractKeyFrame(
                from: asset,
                at: keyFrameTime
            )
        } catch {
            throw ConversionError.imageGenerationFailed
        }

        try Task.checkCancellation()
        progressHandler(0.30)

        // MARK: 5. 写入图片元数据（JPEG + Apple Maker Note）
        let imageURL = tempFileManager.createTempURL(extension: "jpg")
        tempFiles.append(imageURL)

        do {
            try metadataWriter.writeImageMetadata(
                image: keyFrameImage,
                to: imageURL,
                identifier: identifier
            )
        } catch {
            throw ConversionError.imageGenerationFailed
        }

        try Task.checkCancellation()
        progressHandler(0.40)

        // MARK: 6. 处理视频（裁剪 + 元数据）

        // 6a. 裁剪视频（如需要）
        // 判断是否需要裁剪：设置了最大时长且小于原视频时长
        let needsClipping: Bool = {
            guard let maxDuration = maxVideoDuration else { return false }
            return maxDuration > 0 && maxDuration < videoDuration
        }()

        // 用于元数据写入的视频资源和有效时长
        let sourceAssetForMetadata: AVAsset
        let effectiveDuration: Double

        if needsClipping, let clipDuration = maxVideoDuration {
            // 需要裁剪：导出裁剪后的视频到临时文件
            let clippedVideoURL = tempFileManager.createTempURL(extension: "mov")
            tempFiles.append(clippedVideoURL)

            do {
                _ = try await videoProcessor.clipVideo(
                    asset: asset,
                    duration: clipDuration,
                    to: clippedVideoURL,
                    preset: exportPreset
                )
                sourceAssetForMetadata = AVURLAsset(url: clippedVideoURL)
                effectiveDuration = clipDuration
            } catch {
                throw ConversionError.videoProcessingFailed
            }
        } else {
            // 不需要裁剪：直接使用原始视频资源
            sourceAssetForMetadata = asset
            effectiveDuration = videoDuration
        }

        try Task.checkCancellation()
        progressHandler(0.60)

        // 6b. 写入视频元数据（content identifier + still-image-time）
        let finalVideoURL = tempFileManager.createTempURL(extension: "mov")
        tempFiles.append(finalVideoURL)

        // 计算封面帧在最终视频中的时间位置
        // 使用有效时长（裁剪后的时长）来计算
        let stillImageTimeSeconds = coverFramePosition.timestamp(forDuration: effectiveDuration)
        let stillImageTime = CMTime(
            seconds: stillImageTimeSeconds,
            preferredTimescale: 600
        )

        do {
            try await metadataWriter.writeVideoMetadata(
                asset: sourceAssetForMetadata,
                to: finalVideoURL,
                identifier: identifier,
                stillImageTime: stillImageTime
            )
        } catch {
            throw ConversionError.videoProcessingFailed
        }

        try Task.checkCancellation()
        progressHandler(0.80)

        // MARK: 7. 保存 Live Photo 到相册
        // 使用 shouldMoveFile = false（复制模式），更安全
        // 临时文件会在 defer 中统一清理
        do {
            try await photoLibraryManager.saveLivePhoto(
                imageURL: imageURL,
                videoURL: finalVideoURL,
                shouldMoveFile: false
            )
        } catch {
            throw ConversionError.saveFailed
        }

        progressHandler(0.95)

        // MARK: 8. 清理临时文件
        // defer 块会自动执行清理

        progressHandler(1.0)
    }
}
