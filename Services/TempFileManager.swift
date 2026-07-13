import Foundation

/// 临时文件管理器
///
/// 负责在系统临时目录中创建唯一的临时文件 URL，
/// 并在 Live Photo 转换流程完成后统一清理。
/// 所有临时文件（图片、视频）的生命周期均由本类管理。
final class TempFileManager {

    /// 共享单例
    static let shared = TempFileManager()

    /// 私有初始化，确保单例模式
    private init() {}

    // MARK: - 临时文件创建

    /// 在系统临时目录中创建一个唯一的临时文件 URL
    ///
    /// 使用 UUID 生成唯一文件名，避免并发转换时文件名冲突。
    /// 注意：此方法仅生成 URL，不创建实际文件。
    /// - Parameter ext: 文件扩展名（不含点号），例如 "jpg"、"mov"
    /// - Returns: 新创建的临时文件 URL
    func createTempURL(extension ext: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString
        return tempDir
            .appendingPathComponent(fileName)
            .appendingPathExtension(ext)
    }

    // MARK: - 临时文件清理

    /// 删除指定的临时文件
    ///
    /// 如果文件不存在则静默跳过；如果删除失败仅打印日志，不抛出错误，
    /// 以确保清理流程不会中断后续转换步骤。
    /// - Parameter url: 要删除的文件 URL
    func cleanup(url: URL) {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            print("[TempFileManager] 清理临时文件失败: \(url.lastPathComponent) - \(error.localizedDescription)")
        }
    }

    /// 批量清理临时文件
    ///
    /// 遍历 URL 数组逐一删除，单个文件删除失败不影响其他文件。
    /// - Parameter urls: 要删除的文件 URL 数组
    func cleanupAll(urls: [URL]) {
        for url in urls {
            cleanup(url: url)
        }
    }
}
