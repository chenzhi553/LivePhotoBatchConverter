import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 元数据写入错误
///
/// 定义 Live Photo 元数据写入过程中可能出现的错误类型。
enum MetadataWriterError: Error, LocalizedError {
    /// 无法创建图片写入目标（CGImageDestination）
    case imageDestinationCreationFailed
    /// 图片写入失败（CGImageDestinationFinalize 返回 false）
    case imageWriteFailed
    /// 视频轨道不存在
    case noVideoTrack
    /// 视频合成（AVMutableComposition）创建失败
    case compositionFailed
    /// 元数据轨道创建失败
    case metadataTrackCreationFailed
    /// 无法创建导出会话
    case exportSessionCreationFailed
    /// 视频导出失败
    case exportFailed
    /// 视频导出已取消
    case exportCancelled

    var errorDescription: String? {
        switch self {
        case .imageDestinationCreationFailed:
            return "无法创建图片写入目标"
        case .imageWriteFailed:
            return "图片元数据写入失败"
        case .noVideoTrack:
            return "视频轨道不存在"
        case .compositionFailed:
            return "视频合成失败"
        case .metadataTrackCreationFailed:
            return "元数据轨道创建失败"
        case .exportSessionCreationFailed:
            return "无法创建视频导出会话"
        case .exportFailed:
            return "视频元数据导出失败"
        case .exportCancelled:
            return "视频元数据导出已取消"
        }
    }
}

/// Live Photo 元数据写入器
///
/// 负责生成 Live Photo 所需的配对标识符，
/// 并将标识符写入图片（JPEG Apple 元数据）和视频（QuickTime 元数据轨道）。
///
/// Live Photo 元数据原理：
/// 1. **图片元数据**：在 JPEG 的 Apple Maker Note 中设置 `["17": identifier]`，
///    系统通过此元数据识别静态图片所属的 Live Photo。
/// 2. **视频元数据**：在 MOV 文件中写入两条元数据：
///    - `com.apple.quicktime.content.identifier`：与图片标识符配对的电影级元数据
///    - `com.apple.quicktime.still-image-time`：标记封面帧时间位置的定时元数据轨道
///
/// 图片和视频必须共享相同的 content identifier 才能被系统识别为 Live Photo。
final class MetadataWriter {

    /// 共享单例
    static let shared = MetadataWriter()

    /// 私有初始化，确保单例模式
    private init() {}

    // MARK: - 标识符生成

    /// 生成 Live Photo 配对标识符
    ///
    /// 生成一个 UUID 字符串，用于同时写入图片和视频元数据，
    /// 使系统能将两者配对识别为 Live Photo。
    /// 同一次转换中，图片和视频必须使用相同的标识符。
    ///
    /// - Returns: UUID 格式的标识符字符串
    static func generateIdentifier() -> String {
        return UUID().uuidString
    }

    // MARK: - 图片元数据写入

    /// 将 Live Photo 标识符写入 JPEG 图片元数据
    ///
    /// 使用 `CGImageDestination` 将 CGImage 写入 JPEG 文件，
    /// 并在 Apple Maker Note 字典中设置 `["17": identifier]`。
    /// 键 "17" 是 Apple 内部用于存储 Live Photo content identifier 的 Maker Note 键。
    ///
    /// - Parameters:
    ///   - image: 要写入的 CGImage（通常为视频关键帧）
    ///   - url: 输出 JPEG 文件 URL
    ///   - identifier: Live Photo 配对标识符（与视频中的 content identifier 一致）
    /// - Throws: 图片目标创建或写入失败时抛出 `MetadataWriterError`
    func writeImageMetadata(image: CGImage, to url: URL, identifier: String) throws {
        // 创建 JPEG 图片写入目标
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,  // 图片数量
            nil
        ) else {
            throw MetadataWriterError.imageDestinationCreationFailed
        }

        // 构建 Apple Maker Note 元数据
        // kCGImagePropertyMakerAppleDictionary 对应 Apple 设备的 Maker Note
        // 键 "17" 存储 Live Photo 的 content identifier
        let properties: [String: Any] = [
            kCGImagePropertyMakerAppleDictionary as String: ["17": identifier]
        ]

        // 添加图片及元数据到目标
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        // 完成写入（将缓冲区数据刷新到磁盘）
        guard CGImageDestinationFinalize(destination) else {
            throw MetadataWriterError.imageWriteFailed
        }
    }

    // MARK: - 视频元数据写入

    /// 将 Live Photo 元数据写入视频文件
    ///
    /// 使用 `AVMutableComposition` 组合视频、音频和元数据轨道，
    /// 再通过 `AVAssetExportSession`（Passthrough 模式）导出，
    /// 同时写入两条关键元数据：
    ///
    /// 1. **content identifier**（`com.apple.quicktime.content.identifier`）：
    ///    作为电影级元数据，通过 `exportSession.metadata` 设置，
    ///    与图片中的标识符配对。
    ///
    /// 2. **still-image-time**（`com.apple.quicktime.still-image-time`）：
    ///    作为定时元数据轨道写入，标记封面帧在视频中的精确时间位置。
    ///    通过 `AVMutableMetadataTrack` + `AVTimedMetadataGroup` 实现。
    ///    元数据值固定为 0，数据类型为 `com.apple.metadata.datatype.int8`，
    ///    时间范围的起始点即为封面帧时间戳。
    ///
    /// - Parameters:
    ///   - asset: 源视频资源（已裁剪或原始视频）
    ///   - url: 输出 MOV 文件 URL
    ///   - identifier: Live Photo 配对标识符（与图片一致）
    ///   - stillImageTime: 封面帧在视频中的时间位置
    /// - Throws: 视频处理或导出失败时抛出 `MetadataWriterError`
    func writeVideoMetadata(
        asset: AVAsset,
        to url: URL,
        identifier: String,
        stillImageTime: CMTime
    ) async throws {
        let composition = AVMutableComposition()
        let assetDuration = try await asset.load(.duration)
        let fullRange = CMTimeRange(start: .zero, duration: assetDuration)

        // MARK: 复制视频轨道
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw MetadataWriterError.noVideoTrack
        }

        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MetadataWriterError.compositionFailed
        }
        try videoTrack.insertTimeRange(fullRange, of: sourceVideoTrack, at: .zero)
        // 保留原始视频的方向变换（如旋转），确保导出后方向正确
        videoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        // MARK: 复制音频轨道（如果存在）
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let sourceAudioTrack = audioTracks.first {
            if let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try? audioTrack.insertTimeRange(fullRange, of: sourceAudioTrack, at: .zero)
            }
        }

        // MARK: 创建 still-image-time 定时元数据轨道
        // AVMutableMetadataTrack 是 AVMutableCompositionTrack 的子类，
        // 专门用于管理定时元数据组
        guard let metadataTrack = composition.addMutableTrack(
            withMediaType: .metadata,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) as? AVMutableMetadataTrack else {
            throw MetadataWriterError.metadataTrackCreationFailed
        }

        // 构建 still-image-time 元数据项
        let stillImageTimeItem = AVMutableMetadataItem()
        stillImageTimeItem.key = "com.apple.quicktime.still-image-time" as NSString
        stillImageTimeItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        // 值固定为 0，表示封面帧标记
        stillImageTimeItem.value = NSNumber(value: 0)
        // 数据类型指定为 int8，Apple 内部约定的数据格式
        stillImageTimeItem.dataType = "com.apple.metadata.datatype.int8"

        // 构建定时元数据组
        // timeRange.start 指定封面帧在视频中的精确时间位置
        // duration 为一帧的时长（1/600 秒）
        let metadataTimeRange = CMTimeRange(
            start: stillImageTime,
            duration: CMTime(value: 1, timescale: 600)
        )
        let metadataGroup = AVTimedMetadataGroup(
            items: [stillImageTimeItem],
            timeRange: metadataTimeRange
        )
        // 将定时元数据组添加到元数据轨道
        metadataTrack.add(metadataGroup)

        // MARK: 构建 content identifier 电影级元数据
        // 通过 exportSession.metadata 写入到输出文件的电影级元数据中
        let identifierItem = AVMutableMetadataItem()
        identifierItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
        identifierItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        identifierItem.value = identifier as NSString

        // MARK: 导出视频
        // 使用 Passthrough 模式，不重新编码视频/音频流，仅复制并添加元数据
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw MetadataWriterError.exportSessionCreationFailed
        }

        // 确保输出文件不存在
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }

        exportSession.outputURL = url
        exportSession.outputFileType = .mov
        // 设置电影级元数据（content identifier）
        exportSession.metadata = [identifierItem]

        // 执行导出
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        // 检查导出结果
        switch exportSession.status {
        case .completed:
            break
        case .failed:
            throw exportSession.error ?? MetadataWriterError.exportFailed
        case .cancelled:
            throw MetadataWriterError.exportCancelled
        default:
            throw MetadataWriterError.exportFailed
        }
    }

    // MARK: - 时间范围计算

    /// 计算封面帧（still-image-time）的时间范围
    ///
    /// 根据视频总时长、封面帧位置百分比和帧率，
    /// 计算出封面帧在视频中的精确 CMTimeRange。
    /// 该时间范围的起始点即为封面帧的时间戳，持续时长为一帧。
    ///
    /// - Parameters:
    ///   - duration: 视频总时长（秒）
    ///   - percent: 封面帧位置百分比（0.0 ~ 1.0），0.0 表示视频起始，1.0 表示视频末尾
    ///   - fps: 视频帧率（帧/秒），用于计算单帧时长
    /// - Returns: 封面帧的 CMTimeRange，start 为帧时间戳，duration 为单帧时长
    static func makeStillImageTimeRange(duration: Double, percent: Double, fps: Double) -> CMTimeRange {
        // 钳制百分比到 [0.0, 1.0] 范围
        let clampedPercent = max(0.0, min(1.0, percent))
        let startTime = duration * clampedPercent

        // 计算单帧时长（秒），确保 fps 至少为 1 避免除零
        let frameDuration = 1.0 / max(1.0, fps)

        let start = CMTime(seconds: startTime, preferredTimescale: 600)
        let rangeDuration = CMTime(seconds: frameDuration, preferredTimescale: 600)

        return CMTimeRange(start: start, duration: rangeDuration)
    }
}
