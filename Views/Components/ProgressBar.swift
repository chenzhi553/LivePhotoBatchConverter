import SwiftUI

/// 自定义进度条组件
///
/// 圆角矩形样式，带平滑动画过渡效果。
/// 用于显示单个任务或整体转换进度。
struct ProgressBar: View {

    /// 进度值，取值范围 0.0 ~ 1.0（超出范围会自动钳制）
    let value: Double

    /// 进度条填充颜色，默认为蓝色
    var color: Color = .blue

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景轨道
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))

                // 进度填充
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: clampedWidth(geometry.size.width))
                    .animation(.easeInOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 6) // 固定高度 6pt
    }

    /// 根据进度值计算钳制后的填充宽度
    /// - Parameter totalWidth: 进度条总宽度
    /// - Returns: 当前进度对应的填充宽度
    private func clampedWidth(_ totalWidth: CGFloat) -> CGFloat {
        // 将 value 钳制在 0 ~ 1 范围内，避免负数或越界
        let clamped = max(0, min(value, 1))
        return CGFloat(clamped) * totalWidth
    }
}

// MARK: - 预览

#Preview {
    VStack(spacing: 20) {
        ProgressBar(value: 0.3)
        ProgressBar(value: 0.7, color: .green)
        ProgressBar(value: 1.0, color: .red)
    }
    .padding()
}
