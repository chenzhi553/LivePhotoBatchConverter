import Foundation
import UIKit

/// 转换任务模型
///
/// 表示一个视频到 Live Photo 的转换任务，
/// 包含视频源信息、缩略图、转换状态与实时进度。
/// 遵循 `Identifiable` 以便在 SwiftUI 列表中使用，
/// 遵循 `Equatable` 以支持基于差异的视图更新。
struct ConversionTask: Identifiable, Equatable {

    // MARK: - 属性

    /// 唯一标识符
    let id: UUID

    /// PhotoKit 中的资源标识符，用于从相册获取视频
    let assetIdentifier: String

    /// 视频文件 URL（若视频已导出至本地临时目录则存在）
    var videoURL: URL?

    /// 视频总时长（单位：秒）
    var duration: Double

    /// 视频文件名（用于 UI 展示）
    var fileName: String

    /// 视频缩略图（封面帧预览）
    var thumbnail: UIImage?

    /// 当前转换状态
    var status: ConversionStatus

    /// 转换进度，取值范围 0.0 ~ 1.0
    var progress: Double

    /// 任务创建时间
    var createdAt: Date

    /// 错误信息（仅在状态为 `.failed` 时有值）
    var errorMessage: String?

    // MARK: - 初始化

    /// 创建一个转换任务
    /// - Parameters:
    ///   - id: 唯一标识符，默认自动生成
    ///   - assetIdentifier: PhotoKit 资源标识符
    ///   - videoURL: 视频文件本地 URL，默认为 nil
    ///   - duration: 视频时长（秒），默认为 0
    ///   - fileName: 视频文件名
    ///   - thumbnail: 缩略图，默认为 nil
    ///   - status: 初始状态，默认为 `.pending`
    ///   - progress: 初始进度，默认为 0
    ///   - createdAt: 创建时间，默认为当前时间
    ///   - errorMessage: 错误信息，默认为 nil
    init(
        id: UUID = UUID(),
        assetIdentifier: String,
        videoURL: URL? = nil,
        duration: Double = 0,
        fileName: String,
        thumbnail: UIImage? = nil,
        status: ConversionStatus = .pending,
        progress: Double = 0,
        createdAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.assetIdentifier = assetIdentifier
        self.videoURL = videoURL
        self.duration = duration
        self.fileName = fileName
        self.thumbnail = thumbnail
        self.status = status
        self.progress = progress
        self.createdAt = createdAt
        self.errorMessage = errorMessage
    }
}
