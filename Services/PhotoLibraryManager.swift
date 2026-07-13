import Foundation
import Photos

/// 相册管理服务
///
/// 负责请求相册访问权限，以及将配对的图片和视频
/// 保存为 Live Photo 到用户相册。
///
/// Live Photo 保存原理：
/// 使用 `PHAssetCreationRequest` 创建一个新资源，
/// 将 JPEG 图片以 `.photo` 类型、MOV 视频以 `.pairedVideo` 类型添加为配对资源。
/// 两个文件必须共享相同的 content identifier 元数据，系统才能将它们识别为 Live Photo。
final class PhotoLibraryManager {

    /// 共享单例
    static let shared = PhotoLibraryManager()

    /// 私有初始化，确保单例模式
    private init() {}

    // MARK: - 权限请求

    /// 请求相册访问权限
    ///
    /// 使用 `.readWrite` 级别，因为本应用不仅需要向相册写入 Live Photo，
    /// 还需要读取相册中的视频资源（通过 PHAsset 获取视频 URL 和缩略图）。
    ///
    /// - Returns: 当前授权状态（`.authorized` 或 `.limited` 表示可以访问）
    @discardableResult
    func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Live Photo 保存

    /// 将配对的图片和视频保存为 Live Photo
    ///
    /// 通过 `PHPhotoLibrary.performChanges` 在后台线程执行相册写入操作。
    /// 使用 `PHAssetCreationRequest.forAsset()` 创建新资源，并添加两个配对资源：
    /// - `.photo`：包含 Apple Maker Note 元数据的 JPEG 图片
    /// - `.pairedVideo`：包含 content identifier 和 still-image-time 元数据的 MOV 视频
    ///
    /// - Parameters:
    ///   - imageURL: 包含 Live Photo 标识符的 JPEG 图片文件 URL
    ///   - videoURL: 包含 Live Photo 标识符和封面帧时间戳的 MOV 视频文件 URL
    ///   - shouldMoveFile: 是否移动文件而非复制。
    ///     - `true`：原文件被移动到相册管理目录（适用于临时文件，节省磁盘空间）
    ///     - `false`：复制文件（默认值，更安全，保存失败时原文件仍存在）
    /// - Throws: 保存失败时抛出相库错误或自定义错误
    func saveLivePhoto(
        imageURL: URL,
        videoURL: URL,
        shouldMoveFile: Bool = false
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                // 创建 Live Photo 资源请求
                let creationRequest = PHAssetCreationRequest.forAsset()

                // 根据是否移动文件构建资源选项
                let resourceOptions: PHAssetResourceCreationOptions?
                if shouldMoveFile {
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    resourceOptions = options
                } else {
                    resourceOptions = nil
                }

                // 添加图片资源（.photo 类型）
                // 图片包含 Apple Maker Note ["17": identifier] 元数据
                creationRequest.addResource(
                    with: .photo,
                    fileURL: imageURL,
                    options: resourceOptions
                )

                // 添加配对视频资源（.pairedVideo 类型）
                // 视频包含 com.apple.quicktime.content.identifier 和 still-image-time 元数据
                creationRequest.addResource(
                    with: .pairedVideo,
                    fileURL: videoURL,
                    options: resourceOptions
                )
            }, completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    // 未知错误：成功标志为 false 但无错误对象
                    let unknownError = NSError(
                        domain: "PhotoLibraryManager",
                        code: -1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "保存 Live Photo 时发生未知错误"
                        ]
                    )
                    continuation.resume(throwing: unknownError)
                }
            })
        }
    }
}
