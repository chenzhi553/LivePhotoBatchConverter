import Foundation
import Photos
import SwiftUI
import UserNotifications
import AVFoundation

/// 批量转换视图模型
///
/// 管理转换任务队列，控制串行执行（一次只处理一个视频），
/// 发布进度更新到 UI 层。使用 `@MainActor` 确保所有 UI 更新在主线程。
@MainActor
final class BatchViewModel: ObservableObject {

    // MARK: - 发布属性

    /// 转换任务列表
    @Published var tasks: [ConversionTask] = []

    /// 是否正在转换中
    @Published var isConverting: Bool = false

    /// 整体进度（0.0 ~ 1.0）
    @Published var overallProgress: Double = 0.0

    /// 用户设置
    @Published var settings: LivePhotoSettings = LivePhotoSettings()

    /// 错误提示（用于弹窗显示）
    @Published var errorMessage: String?

    // MARK: - 私有属性

    /// 当前转换任务的 Task，用于支持取消
    private var conversionTask: Task<Void, Never>?

    // MARK: - 任务管理

    /// 从 PHAsset 数组创建转换任务
    ///
    /// 为每个 PHAsset 创建 ConversionTask，异步提取缩略图。
    /// 不会阻塞主线程。
    ///
    /// - Parameter assets: 用户选择的 PHAsset 数组
    func addTasks(assets: [PHAsset]) {
        guard !assets.isEmpty else { return }

        for asset in assets {
            // 安全获取文件名：避免 KVC 崩溃
            let fileName = safeGetFileName(from: asset)
            let duration = asset.duration

            let task = ConversionTask(
                assetIdentifier: asset.localIdentifier,
                duration: duration,
                fileName: fileName
            )
            tasks.append(task)

            // 异步加载缩略图
            loadThumbnail(for: task.id, asset: asset)
        }
    }

    /// 安全获取视频文件名
    /// 不使用 KVC（value(forKey:)），避免 ObjC 异常崩溃
    private func safeGetFileName(from asset: PHAsset) -> String {
        // PHAssetResource 可以安全获取文件名
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            let originalFilename = resource.originalFilename
            if !originalFilename.isEmpty {
                return originalFilename
            }
        }
        // 回退：使用 localIdentifier 的一部分
        return "视频_\(asset.localIdentifier.prefix(8))"
    }

    /// 异步加载视频缩略图
    ///
    /// **关键修复**：使用 `.highQualityFormat` 交付模式确保回调只触发一次。
    /// 之前的 `.opportunistic` 模式会多次回调，导致 CheckedContinuation
    /// 被 resume 多次而崩溃。
    private func loadThumbnail(for taskId: UUID, asset: PHAsset) {
        Task.detached { [weak self] in
            let options = PHImageRequestOptions()
            // ✅ 修复：使用 highQualityFormat 确保只回调一次
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            options.resizeMode = .fast

            let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: 200, height: 200),
                    contentMode: .aspectFill,
                    options: options
                ) { image, _ in
                    continuation.resume(returning: image)
                }
            }

            await MainActor.run {
                self?.updateTask(id: taskId) { task in
                    task.thumbnail = image
                }
            }
        }
    }

    /// 移除单个任务
    /// - Parameter id: 任务 ID
    func removeTask(id: UUID) {
        tasks.removeAll { $0.id == id }
    }

    /// 清空所有任务
    func clearTasks() {
        guard !isConverting else { return }
        tasks.removeAll()
        overallProgress = 0.0
    }

    // MARK: - 转换流程

    /// 开始批量转换
    ///
    /// 串行处理所有待转换任务（一次只处理一个视频，避免内存峰值）。
    /// 转换完成后发送本地通知。
    func startConversion() {
        guard !isConverting else { return }

        let pendingTasks = tasks.filter {
            if case .completed = $0.status { return false }
            return true
        }
        guard !pendingTasks.isEmpty else { return }

        isConverting = true
        overallProgress = 0.0

        // 获取任务 ID 快照，防止数组变化导致索引错位
        let taskIds = pendingTasks.map { $0.id }
        let totalCount = taskIds.count
        let settings = self.settings

        conversionTask = Task { [weak self] in
            var completedCount = 0

            for taskId in taskIds {
                if Task.isCancelled { break }

                // 标记为处理中
                self?.updateTask(id: taskId) { task in
                    task.status = .processing
                    task.progress = 0.0
                    task.errorMessage = nil
                }

                // 获取当前任务
                guard let currentTask = self?.tasks.first(where: { $0.id == taskId }) else {
                    completedCount += 1
                    continue
                }

                // 获取 PHAsset
                guard let asset = self?.fetchPHAsset(withIdentifier: currentTask.assetIdentifier) else {
                    self?.updateTask(id: taskId) { t in
                        t.status = .failed("找不到相册资源")
                        t.errorMessage = "找不到相册资源"
                    }
                    completedCount += 1
                    continue
                }

                // 获取视频文件 URL
                guard let videoURL = await self?.requestVideoURL(from: asset) else {
                    self?.updateTask(id: taskId) { t in
                        t.status = .failed("无法获取视频文件")
                        t.errorMessage = "无法获取视频文件"
                    }
                    completedCount += 1
                    continue
                }

                // 执行转换
                do {
                    try await LivePhotoConverter.convert(
                        videoURL: videoURL,
                        settings: settings
                    ) { progress in
                        self?.updateTask(id: taskId) { t in
                            t.progress = progress
                        }
                    }

                    // 转换成功
                    self?.updateTask(id: taskId) { t in
                        t.status = .completed
                        t.progress = 1.0
                    }
                } catch {
                    // 转换失败
                    self?.updateTask(id: taskId) { t in
                        t.status = .failed(error.localizedDescription)
                        t.errorMessage = error.localizedDescription
                    }
                }

                completedCount += 1
                self?.overallProgress = Double(completedCount) / Double(totalCount)
            }

            // 转换完成
            self?.isConverting = false
            self?.sendCompletionNotification()
        }
    }

    /// 取消转换
    func cancelConversion() {
        conversionTask?.cancel()
        conversionTask = nil
        isConverting = false

        // 将所有处理中的任务重置为等待
        for i in tasks.indices {
            if tasks[i].status == .processing {
                tasks[i].status = .pending
                tasks[i].progress = 0.0
            }
        }
    }

    // MARK: - 私有方法

    /// 通过 localIdentifier 获取 PHAsset
    private func fetchPHAsset(withIdentifier identifier: String) -> PHAsset? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [identifier],
            options: nil
        )
        return fetchResult.firstObject
    }

    /// 从 PHAsset 获取视频文件 URL
    ///
    /// 双重保障：
    /// 1. 先用 PHImageManager.requestAVAsset 直接获取（本地视频）
    /// 2. 失败则用 PHAssetResourceManager 导出到临时文件（iCloud 视频）
    private func requestVideoURL(from asset: PHAsset) async -> URL? {
        // 方案 1：直接获取 URL（本地视频）
        if let url = await getVideoURLDirect(from: asset) {
            return url
        }

        // 方案 2：导出到临时文件（iCloud 视频或编辑过的视频）
        return await exportVideoToTemp(from: asset)
    }

    /// 直接获取视频 URL
    private func getVideoURLDirect(from asset: PHAsset) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat

            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: options
            ) { avAsset, _, _ in
                if let urlAsset = avAsset as? AVURLAsset {
                    continuation.resume(returning: urlAsset.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 使用 PHAssetResourceManager 导出视频到临时文件
    private func exportVideoToTemp(from asset: PHAsset) async -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let videoResource = resources.first(where: { $0.type == .video }) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true

            PHAssetResourceManager.default().writeData(
                for: videoResource,
                toFile: tempURL,
                options: options
            ) { error in
                if let _ = error {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: tempURL)
                }
            }
        }
    }

    /// 更新指定任务
    private func updateTask(id: UUID, _ update: (inout ConversionTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        update(&tasks[index])
    }

    /// 发送转换完成通知
    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()
        content.title = "转换完成"
        let successCount = tasks.filter { if case .completed = $0.status { return true }; return false }.count
        let failCount = tasks.filter { if case .failed = $0.status { return true }; return false }.count
        content.body = "成功 \(successCount) 个，失败 \(failCount) 个"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "conversion_complete",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
