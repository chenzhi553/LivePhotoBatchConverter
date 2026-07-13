import CoreMedia

extension CMTime {

    /// 格式化时间显示，格式为 "分:秒.十分之一秒"（如 "00:03.5"）
    /// - Returns: 格式化后的时间字符串；如果时间无效则返回 "00:00.0"
    var formattedString: String {
        let totalSeconds = CMTimeGetSeconds(self)

        // 处理无效时间（NaN 或无穷大）
        guard totalSeconds.isFinite && totalSeconds >= 0 else {
            return "00:00.0"
        }

        let minutes = Int(totalSeconds) / 60
        let seconds = totalSeconds - Double(minutes * 60)

        // %02d: 分钟补零为两位
        // %04.1f: 秒数补零为四位（含小数点），保留一位小数
        return String(format: "%02d:%04.1f", minutes, seconds)
    }

    /// 获取指定时长的中间时间点
    /// - Parameter duration: 原始时长
    /// - Returns: 时长的中点
    static func middle(of duration: CMTime) -> CMTime {
        // 使用 CMTimeMultiplyByRatio 进行精确的时间除法运算
        return CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
    }

    /// 便捷初始化方法，使用秒数创建 CMTime
    /// - Parameter seconds: 时间值（秒）
    /// - Note: 默认使用 600 的时间刻度（timescale），这是视频处理中常用的精度
    init(seconds: Double) {
        self = CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
