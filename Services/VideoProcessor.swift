import Foundation
import AVFoundation
import UIKit
import CoreGraphics

/// 视频处理错误
///
/// 定义视频处理过程中可能出现的错误类型。
enum VideoProcessorError: Error, LocalizedError {
    /// 视频轨道不存在
    case noVideoTrack
    /// 无效的视频时长
    case invalidDuration
    /// 无法创建导出会话
    case exportSessionCreationFailed
    /// 视频导出失败
    case exportFailed
    /// 视频导出已取消
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "视频轨道不存在"
        case .invalidDuration:
            return "无效的视频时长"
        case .exportSessionCreationFailed:
            return "无法创建视频导出会话"
        case .exportFailed:
            return "视频导出失败"
        case .exportCancelled:
            return "视频导出已取消"
        }
    }
}

/// 视频处理服务
///
/// 负责视频相关的核心处理操作：
/// - 关键帧提取（用于生成 Live Photo 的静态封面图）
/// - 视频缩略图生成（用于 UI 展示）
/// - 视频裁剪（将视频裁剪到指定时长，并做分辨率对齐）
/// - 视频时长获取
///
/// 所有方法均使用 async/await 异步调用，适配 Swift Concurrency。
final class VideoProcessor {

    /// 共享单例
    static let shared = VideoProcessor()

    /// 私有初始化，确保单例模式
    private init() {}

    // MARK: - 关键帧提取

    /// 提取指定时间点的视频关键帧
    ///
    /// 使用 `AVAssetImageGenerator` 从视频中提取指定时间的帧图像。
    /// 设置 `requestedTimeToleranceBefore/After` 为 `.zero` 以精确提取目标时间点的帧，
    /// 而非最近的关键帧。
    ///
    /// - Parameters:
    ///   - asset: 视频资源
    ///   - time: 目标提取时间点
    /// - Returns: 提取到的 CGImage
    /// - Throws: 视频轨道不存在或帧提取失败时抛出错误
    func extractKeyFrame(from asset: AVAsset, at time: CMTime) async throws -> CGImage {
        // 创建图像生成器
        let generator = AVAssetImageGenerator(asset: asset)
        // 应用轨道的首选变换（如旋转），确保输出图像方向正确
        generator.appliesPreferredTrackTransform = true
        // 设置时间容差为零，确保精确提取指定时间的帧
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // 使用 iOS 16+ 的 async API 提取帧
        let result = try await generator.image(at: time)
        return result.image
    }

    // MARK: - 缩略图生成

    /// 生成视频缩略图
    ///
    /// 从视频中间时间点提取一帧作为缩略图，用于 UI 列表展示。
    ///
    /// - Parameter asset: 视频资源
    /// - Returns: 缩略图 UIImage
    /// - Throws: 时长获取或帧提取失败时抛出错误
    func generateThumbnail(from asset: AVAsset) async throws -> UIImage {
        let duration = try await asset.load(.duration)

        // 取视频中点时间
        let midTime = CMTime(
            seconds: duration.seconds / 2.0,
            preferredTimescale: 600
        )

        // 提取中点帧
        let cgImage = try await extractKeyFrame(from: asset, at: midTime)
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 视频裁剪

    /// 裁剪视频到指定时长
    ///
    /// 使用 `AVAssetExportSession` 裁剪视频的前 `duration` 秒，
    /// 输出格式为 MOV。同时进行分辨率对齐处理：
    /// 将视频的宽高对齐到 16 的整数倍，以优化 H.264/H.265 编码效率。
    ///
    /// 分辨率对齐策略：
    /// 1. 读取视频轨道的 naturalSize 和 preferredTransform
    /// 2. 计算应用变换后的实际显示尺寸
    /// 3. 将宽高各自对齐到最近的 16 的整数倍
    /// 4. 若尺寸发生变化，通过 `AVMutableVideoComposition` 设置渲染尺寸，
    ///    并在 layer instruction 中组合 preferredTransform 和缩放变换
    ///
    /// - Parameters:
    ///   - asset: 原始视频资源
    ///   - duration: 目标裁剪时长（秒）。若超过原视频时长，则裁剪到原视频末尾。
    ///   - outputURL: 输出文件 URL
    ///   - preset: 导出质量预设，默认为最高质量。使用 `OutputQuality.exportPreset` 传入。
    /// - Returns: 裁剪后的视频文件 URL（与 outputURL 相同）
    /// - Throws: 视频轨道缺失、导出会话创建失败或导出过程出错时抛出错误
    func clipVideo(
        asset: AVAsset,
        duration: Double,
        to outputURL: URL,
        preset: String = AVAssetExportPresetHighestQuality
    ) async throws -> URL {
        // MARK: 获取视频时长并计算裁剪范围
        let assetDuration = try await asset.load(.duration)
        let assetSeconds = assetDuration.seconds

        guard assetSeconds > 0 else {
            throw VideoProcessorError.invalidDuration
        }

        // 裁剪时长不超过原视频时长
        let clipDuration = min(duration, assetSeconds)
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )

        // MARK: 获取视频轨道信息
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw VideoProcessorError.noVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        // 计算应用首选变换后的实际显示尺寸
        let transformedSize = naturalSize.applying(preferredTransform)
        let displayWidth = abs(transformedSize.width)
        let displayHeight = abs(transformedSize.height)

        // MARK: 分辨率对齐到 16 的整数倍
        let alignedWidth = CGFloat(Int(round(displayWidth / 16.0)) * 16)
        let alignedHeight = CGFloat(Int(round(displayHeight / 16.0)) * 16)
        let needsAlignment = alignedWidth != displayWidth || alignedHeight != displayHeight

        // MARK: 创建导出会话
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: preset
        ) else {
            throw VideoProcessorError.exportSessionCreationFailed
        }

        // 确保输出文件不存在（避免导出失败）
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.timeRange = timeRange
        exportSession.shouldOptimizeForNetworkUse = true

        // MARK: 设置视频合成（分辨率对齐）
        // 仅在需要对齐且非 Passthrough 预设时应用
        // Passthrough 模式不重新编码，无法修改分辨率
        if needsAlignment && preset != AVAssetExportPresetPassthrough {
            let composition = AVMutableVideoComposition()
            composition.renderSize = CGSize(width: alignedWidth, height: alignedHeight)
            composition.frameDuration = CMTime(value: 1, timescale: 30)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = timeRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)

            // 组合首选变换和缩放变换
            // 先应用 preferredTransform（自然坐标 -> 显示坐标），
            // 再应用缩放变换（显示坐标 -> 对齐坐标），
            // 使视频填满对齐后的渲染区域
            let scaleX = alignedWidth / displayWidth
            let scaleY = alignedHeight / displayHeight
            let scaleTransform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            let finalTransform = preferredTransform.concatenating(scaleTransform)
            layerInstruction.setTransform(finalTransform, at: .zero)

            instruction.layerInstructions = [layerInstruction]
            composition.instructions = [instruction]

            exportSession.videoComposition = composition
        }

        // MARK: 执行导出
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        // MARK: 检查导出结果
        switch exportSession.status {
        case .completed:
            return outputURL
        case .failed:
            throw exportSession.error ?? VideoProcessorError.exportFailed
        case .cancelled:
            throw VideoProcessorError.exportCancelled
        default:
            throw VideoProcessorError.exportFailed
        }
    }

    // MARK: - 视频时长获取

    /// 获取视频时长
    ///
    /// 异步加载视频资源的 duration 属性并返回秒数。
    ///
    /// - Parameter asset: 视频资源
    /// - Returns: 视频时长（秒）
    /// - Throws: 时长无效时抛出错误
    func getVideoDuration(asset: AVAsset) async throws -> Double {
        let cmTime = try await asset.load(.duration)
        let seconds = cmTime.seconds

        guard seconds.isFinite, seconds > 0 else {
            throw VideoProcessorError.invalidDuration
        }

        return seconds
    }
}
