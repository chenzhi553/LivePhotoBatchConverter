import Photos
import SwiftUI
import UserNotifications
import AVFoundation

/// 批量转换 ViewModel，负责管理视频到 Live Photo 的批量转换流程
/// 使用 @MainActor 确保所有 UI 更新在主线程执行
@MainActor
final class BatchViewModel: ObservableObject {

    // MARK: - Published 属性

    /// 所有转换任务列表
    @Published var tasks: [ConversionTask] = []

    /// 是否正在转换中
    @Published var isConverting: Bool = false

    /// 整体转换进度 (0.0 - 1.0)
    @Published var overallProgress: Double = 0.0

    /// Live Photo 转换设置
    @Published var settings: LivePhotoSettings = LivePhotoSettings()

    // MARK: - 私有属性

    /// 当前批量转换的任务句柄，用于支持取消操作
    private var conversionTask: Task<Void, Never>?

    /// 已成功完成的任务数
    private var successCount: Int = 0

    /// 失败的任务数
    private var failedCount: Int = 0

    // MARK: - 任务管理

    /// 从 PHAsset 数组创建转换任务
    /// 自动提取每个视频的缩略图和时长信息
    /// - Parameter assets: 相册资源数组
    func addTasks(assets: [PHAsset]) {
        for asset in assets {
            // 同步获取缩略图
            let thumbnail = requestThumbnail(from: asset)
            // 获取视频文件名（通过 KVC 访问 PHAsset 的私有属性）
            let fileName = (asset.value(forKey: "filename") as? String) ?? "未知视频"

            let task = ConversionTask(
                id: UUID(),
                assetIdentifier: asset.localIdentifier,
                duration: asset.duration,
                fileName: fileName,
                thumbnail: thumbnail,
                status: .pending,
                progress: 0.0
            )
            tasks.append(task)
        }
        Logger.shared.log(info: "已添加 \(assets.count) 个任务，当前共 \(tasks.count) 个任务")
    }

    /// 开始批量转换
    /// 串行处理，一次只处理一个视频，完成后发送本地通知
    func startConversion() {
        guard !isConverting else {
            Logger.shared.log(info: "正在转换中，忽略重复启动请求")
            return
        }
        guard !tasks.isEmpty else {
            Logger.shared.log(info: "任务列表为空，无需转换")
            return
        }

        // 检查是否有待处理的任务
        let hasPendingTasks = tasks.contains { $0.status == .pending }
        guard hasPendingTasks else {
            Logger.shared.log(info: "没有待处理的任务")
            return
        }

        isConverting = true
        overallProgress = 0.0
        successCount = 0
        failedCount = 0

        // 请求本地通知权限
        requestNotificationPermission()

        // 获取所有待处理任务的 ID 快照（防止遍历期间数组变化）
        let pendingTaskIds = tasks.filter { $0.status == .pending }.map { $0.id }
        let totalCount = tasks.count

        Logger.shared.log(info: "开始批量转换，共 \(pendingTaskIds.count) 个待处理任务")

        conversionTask = Task {
            for taskId in pendingTaskIds {
                // 检查是否已取消
                if Task.isCancelled {
                    Logger.shared.log(info: "转换已取消")
                    break
                }

                // 通过 ID 查找任务当前索引（防止数组变化导致索引错位）
                guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
                    Logger.shared.log(debug: "任务已被移除，跳过")
                    continue
                }

                // 标记为处理中
                tasks[index].status = .processing
                tasks[index].progress = 0.0

                do {
                    try await convertTask(at: index)
                    // 转换完成后重新查找索引（await 期间数组可能已变化）
                    if let currentIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                        tasks[currentIndex].status = .completed
                        tasks[currentIndex].progress = 1.0
                    }
                    successCount += 1
                    Logger.shared.log(info: "任务转换成功 (\(successCount + failedCount)/\(pendingTaskIds.count))")
                } catch {
                    if let currentIndex = tasks.firstIndex(where: { $0.id == taskId }) {
                        tasks[currentIndex].status = .failed(error.localizedDescription)
                        tasks[currentIndex].errorMessage = error.localizedDescription
                    }
                    failedCount += 1
                    Logger.shared.log(error: "任务转换失败: \(error.localizedDescription)")
                }

                // 更新整体进度
                let completedTotal = successCount + failedCount
                overallProgress = Double(completedTotal) / Double(max(totalCount, 1))
            }

            isConverting = false
            conversionTask = nil

            // 发送转换完成通知
            sendCompletionNotification()

            Logger.shared.log(info: "批量转换完成，成功: \(successCount)，失败: \(failedCount)")
        }
    }

    /// 取消所有转换任务
    /// 将正在处理的任务重置为等待状态
    func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil

        // 将正在处理的任务重置为等待状态
        for index in tasks.indices {
            if tasks[index].status == .processing {
                tasks[index].status = .pending
                tasks[index].progress = 0.0
            }
        }

        isConverting = false
        Logger.shared.log(info: "已取消所有转换任务")
    }

    /// 清空任务列表
    /// 仅在非转换状态下可执行
    func clearTasks() {
        guard !isConverting else {
            Logger.shared.log(info: "正在转换中，无法清空任务列表")
            return
        }
        tasks.removeAll()
        overallProgress = 0.0
        successCount = 0
        failedCount = 0
        Logger.shared.log(info: "已清空任务列表")
    }

    /// 移除单个任务
    /// - Parameter id: 任务唯一标识
    func removeTask(id: UUID) {
        guard !isConverting else {
            Logger.shared.log(info: "正在转换中，无法移除任务")
            return
        }
        tasks.removeAll { $0.id == id }
        Logger.shared.log(info: "已移除任务，剩余 \(tasks.count) 个任务")
    }

    // MARK: - 私有方法

    /// 转换单个任务
    /// 通过 assetIdentifier 获取 PHAsset，再获取视频 URL 进行转换
    /// - Parameter index: 任务在数组中的索引
    private func convertTask(at index: Int) async throws {
        let task = tasks[index]
        let taskId = task.id

        // 通过 assetIdentifier 从相册获取 PHAsset
        guard let asset = fetchPHAsset(withIdentifier: task.assetIdentifier) else {
            throw ConversionError.assetNotFound
        }

        // 从 PHAsset 获取视频文件 URL
        let videoURL = try await requestVideoURL(from: asset)

        Logger.shared.log(debug: "开始转换视频: \(videoURL.lastPathComponent)")

        // 调用 LivePhotoConverter 进行实际转换
        try await LivePhotoConverter.convert(
            videoURL: videoURL,
            settings: settings
        ) { [weak self] progress in
            guard let self = self else { return }
            Task { @MainActor in
                // 通过 ID 查找索引，确保安全更新
                guard let idx = self.tasks.firstIndex(where: { $0.id == taskId }) else { return }
                self.tasks[idx].progress = progress

                // 更新整体进度（包含当前任务的部分进度）
                let completedTotal = self.successCount + self.failedCount
                let total = max(self.tasks.count, 1)
                self.overallProgress = (Double(completedTotal) + progress) / Double(total)
            }
        }
    }

    /// 通过 assetIdentifier 从相册获取 PHAsset
    /// - Parameter identifier: PHAsset 的本地标识符
    /// - Returns: 对应的 PHAsset，如果未找到则返回 nil
    private func fetchPHAsset(withIdentifier identifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        return fetchResult.firstObject
    }

    /// 从 PHAsset 同步获取缩略图
    /// - Parameter asset: 相册资源
    /// - Returns: 缩略图图片，如果获取失败则返回 nil
    private func requestThumbnail(from asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact

        // 缩略图目标尺寸
        let targetSize = CGSize(width: 400, height: 400)

        var thumbnail: UIImage?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            thumbnail = image
        }
        return thumbnail
    }

    /// 从 PHAsset 异步获取视频文件 URL
    /// - Parameter asset: 相册资源
    /// - Returns: 视频文件的 URL
    private func requestVideoURL(from asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, info in
                // 检查是否有错误信息
                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(throwing: ConversionError.videoURLNotAvailable)
                }
            }
        }
    }

    /// 请求本地通知权限
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                Logger.shared.log(debug: "已获得通知权限")
            } else {
                Logger.shared.log(info: "未获得通知权限，将无法发送完成通知")
            }
        }
    }

    /// 发送转换完成本地通知
    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Live Photo 批量转换完成"

        if failedCount > 0 {
            content.body = "成功转换 \(successCount) 个视频，\(failedCount) 个失败"
        } else {
            content.body = "成功转换 \(successCount) 个视频"
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "com.livephoto.batchconverter.completion",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.log(error: "发送通知失败: \(error.localizedDescription)")
            }
        }
    }
}

