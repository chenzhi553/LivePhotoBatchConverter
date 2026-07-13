import SwiftUI

/// 视频缩略图组件
///
/// 当有图片时显示视频封面帧，无图片时显示灰色占位符（带视频图标）。
/// 圆角 8pt，宽高相等。
struct VideoThumbnail: View {

    /// 缩略图图片，为 nil 时显示占位符
    let image: UIImage?

    /// 缩略图尺寸（宽高相同），默认 50pt
    var size: CGFloat = 50

    var body: some View {
        if let image = image {
            // 有图片：显示视频封面帧
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            // 无图片：显示灰色占位符 + 视频图标
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "video")
                        .foregroundStyle(.secondary)
                }
        }
    }
}

// MARK: - 预览

#Preview {
    HStack(spacing: 16) {
        VideoThumbnail(image: nil, size: 50)
        VideoThumbnail(image: nil, size: 80)
    }
    .padding()
}
