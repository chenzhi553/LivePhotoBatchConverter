import AVFoundation
import CoreGraphics
import ImageIO

extension AVAsset {

    /// 获取视频尺寸（应用 preferredTransform 后的实际显示尺寸）
    /// - Returns: 视频的显示尺寸，如果无法获取视频轨道则返回 nil
    var videoSize: CGSize? {
        guard let track = tracks(withMediaType: .video).first else {
            return nil
        }
        // 将自然尺寸应用首选变换矩阵，得到实际显示尺寸
        let size = track.naturalSize.applying(track.preferredTransform)
        // 取绝对值，因为变换可能导致尺寸为负数
        return CGSize(width: abs(size.width), height: abs(size.height))
    }

    /// 获取视频帧率
    /// - Returns: 视频的标称帧率（fps），如果无法获取视频轨道则返回 0
    var frameRate: Float {
        guard let track = tracks(withMediaType: .video).first else {
            return 0
        }
        return track.nominalFrameRate
    }

    /// 获取视频方向（基于 preferredTransform 变换矩阵）
    /// 通过分析变换矩阵的元素来判断视频的旋转角度
    /// - Returns: 视频的图像方向，默认为 .up（无旋转）
    var orientation: CGImagePropertyOrientation {
        guard let track = tracks(withMediaType: .video).first else {
            return .up
        }
        let t = track.preferredTransform

        // 根据变换矩阵元素判断视频旋转方向
        // 变换矩阵格式: | a  c |
        //              | b  d |
        if t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0 {
            // 顺时针旋转 90 度
            return .right
        } else if t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0 {
            // 逆时针旋转 90 度
            return .left
        } else if t.a == -1 && t.b == 0 && t.c == 0 && t.d == -1 {
            // 旋转 180 度
            return .down
        } else {
            // 默认方向（无旋转）
            return .up
        }
    }
}
