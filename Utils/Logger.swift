import os
import Foundation

/// 日志工具类，使用 os.Logger 统一管理应用日志输出
/// 通过 Logger.shared 访问共享实例
final class Logger {

    /// 共享日志实例，全局唯一
    static let shared = Logger()

    /// 底层 os.Logger 实例，subsystem 为应用标识
    private let internalLogger = os.Logger(
        subsystem: "com.livephoto.batchconverter",
        category: "app"
    )

    /// 私有初始化方法，确保单例模式
    private init() {}

    /// 记录错误级别日志
    /// - Parameter error: 错误信息描述
    func log(error: String) {
        internalLogger.error("[ERROR] \(error, privacy: .public)")
    }

    /// 记录信息级别日志
    /// - Parameter info: 信息内容描述
    func log(info: String) {
        internalLogger.info("[INFO] \(info, privacy: .public)")
    }

    /// 记录调试级别日志
    /// - Parameter debug: 调试信息描述
    func log(debug: String) {
        internalLogger.debug("[DEBUG] \(debug, privacy: .public)")
    }
}
