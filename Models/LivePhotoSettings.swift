import Foundation
import Combine
import AVFoundation

// MARK: - 封面帧位置

/// 封面帧位置枚举
///
/// 决定从视频中截取哪一帧作为 Live Photo 的静态封面图。
/// 遵循 `Hashable` 以便在 SwiftUI 的 `Picker` 中作为 `tag` 使用。
enum CoverFramePosition: Equatable, Hashable {

    /// 视频起始帧（第 0 秒）
    case beginning

    /// 视频中间帧（时长 / 2）
    case middle

    /// 自定义时间点
    /// - Parameter TimeInterval: 时间位置（单位：秒）
    case custom(TimeInterval)

    /// 根据视频总时长计算具体的封面帧时间点
    /// - Parameter duration: 视频总时长（秒）
    /// - Returns: 封面帧在视频中的时间位置（秒），自动钳制在 `[0, duration]` 范围内
    func timestamp(forDuration duration: TimeInterval) -> TimeInterval {
        switch self {
        case .beginning:
            return 0
        case .middle:
            return duration / 2
        case .custom(let time):
            // 确保自定义时间不超过视频时长，且不为负数
            return max(0, min(time, duration))
        }
    }

    /// 在 UI 中展示的名称
    var displayName: String {
        switch self {
        case .beginning:
            return "起始帧"
        case .middle:
            return "中间帧"
        case .custom:
            return "自定义"
        }
    }
}

// MARK: - 输出质量

/// 输出质量枚举
///
/// 控制导出视频和生成 Live Photo 时的画质与文件体积。
/// 遵循 `CaseIterable` 和 `Identifiable` 以便在 SwiftUI 的 `Picker` / `ForEach` 中使用。
enum OutputQuality: String, CaseIterable, Identifiable {

    /// 标准质量（文件体积较小，适合日常分享）
    case standard

    /// 高质量（文件体积较大，画质更佳）
    case high

    // MARK: Identifiable

    var id: String { rawValue }

    // MARK: UI 展示

    /// 在 UI 中展示的名称
    var displayName: String {
        switch self {
        case .standard:
            return "标准"
        case .high:
            return "高质量"
        }
    }

    // MARK: 导出配置

    /// 对应的 AVAssetExportSession 预设名称
    var exportPreset: String {
        switch self {
        case .standard:
            return AVAssetExportPresetMediumQuality
        case .high:
            return AVAssetExportPresetHighestQuality
        }
    }
}

// MARK: - 用户设置模型

/// 用户设置模型
///
/// 管理视频转 Live Photo 的各项转换参数。
/// 通过 `ObservableObject` + `@Published` 实现 SwiftUI 数据绑定，
/// 当任意设置项变更时，依赖此对象的视图会自动刷新。
final class LivePhotoSettings: ObservableObject {

    /// 封面帧位置，默认取视频中间帧
    @Published var coverFramePosition: CoverFramePosition = .middle

    /// 最大视频时长（单位：秒）。
    /// - `nil`：不裁剪视频，保留原始时长
    /// - 非空值：将视频裁剪至指定时长
    /// 默认限制为 3 秒
    @Published var maxVideoDuration: TimeInterval? = 3

    /// 输出质量，默认为标准质量
    @Published var outputQuality: OutputQuality = .standard
}
