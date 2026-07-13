import SwiftUI

/// 转换状态枚举，表示视频转 Live Photo 任务的不同状态
enum ConversionStatus: Equatable {
    /// 等待中：任务已创建，尚未开始转换
    case pending
    /// 转换中：任务正在处理
    case processing
    /// 已完成：任务转换成功
    case completed
    /// 失败：任务转换失败，附带错误信息
    case failed(String)

    /// 对应的 SF Symbol 图标名称
    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .processing: return "arrow.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    /// 状态对应的显示颜色
    var color: Color {
        switch self {
        case .pending: return .gray
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }

    /// 状态对应的中文显示文本
    var displayText: String {
        switch self {
        case .pending: return "等待中"
        case .processing: return "转换中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}
