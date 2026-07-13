import SwiftUI

/// 单个转换任务行视图
///
/// 在任务列表中展示单个视频转换任务的信息，包括：
/// - 左侧：视频缩略图（50x50，圆角 8）
/// - 中间：文件名（粗体）、时长（灰色小字）、状态文字/进度条/错误信息
/// - 右侧：状态图标（颜色与状态对应）
struct TaskRowView: View {

    /// 当前要展示的转换任务
    let task: ConversionTask

    var body: some View {
        HStack(spacing: 12) {
            // 左侧：视频缩略图
            VideoThumbnail(image: task.thumbnail, size: 50)

            // 中间：任务信息
            VStack(alignment: .leading, spacing: 4) {
                // 文件名（粗体）
                Text(task.fileName)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .lineLimit(1)

                // 时长（灰色小字）
                Text(formatDuration(task.duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // 根据状态显示不同内容
                if task.status == .processing {
                    // 转换中：显示小型进度条
                    ProgressBar(value: task.progress, color: .blue)
                        .frame(height: 4)

                    Text("\(task.status.displayText) \(Int(task.progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(task.status.color)

                } else if case .failed = task.status {
                    // 失败：显示错误信息（红色小字）
                    Text(task.errorMessage ?? task.status.displayText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)

                } else {
                    // 等待中 / 已完成：显示状态文字
                    Text(task.status.displayText)
                        .font(.caption)
                        .foregroundStyle(task.status.color)
                }
            }

            Spacer(minLength: 4)

            // 右侧：状态图标
            Image(systemName: task.status.iconName)
                .foregroundStyle(task.status.color)
                .font(.title3)
        }
        .padding(.vertical, 4)
    }

    /// 将秒数格式化为 "分:秒" 形式（如 1:05）
    /// - Parameter seconds: 视频时长（秒）
    /// - Returns: 格式化后的时长字符串
    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - 预览

#Preview {
    List {
        TaskRowView(task: ConversionTask(
            assetIdentifier: "1",
            duration: 12.5,
            fileName: "示例视频.mp4",
            status: .pending
        ))
        TaskRowView(task: ConversionTask(
            assetIdentifier: "2",
            duration: 65.0,
            fileName: "转换中的视频.mov",
            status: .processing,
            progress: 0.45
        ))
        TaskRowView(task: ConversionTask(
            assetIdentifier: "3",
            duration: 3.0,
            fileName: "已完成的视频.mp4",
            status: .completed,
            progress: 1.0
        ))
        TaskRowView(task: ConversionTask(
            assetIdentifier: "4",
            duration: 8.2,
            fileName: "失败的视频.mp4",
            status: .failed("无法获取视频文件"),
            errorMessage: "无法获取视频文件"
        ))
    }
}
