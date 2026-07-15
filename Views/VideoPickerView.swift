import SwiftUI
import Photos
import PhotosUI

/// 视频选择页（主页面）
///
/// 应用的入口页面，用户在此：
/// - 通过 PHPicker 选择视频
/// - 一键全选相册中的所有视频
/// - 查看已添加的任务列表
/// - 启动批量转换或取消转换
/// - 进入设置页调整参数
struct VideoPickerView: View {

    /// 批量转换视图模型（通过环境注入）
    @EnvironmentObject private var viewModel: BatchViewModel

    /// 当前激活的 sheet 类型
    @State private var activeSheet: ActiveSheet?

    /// 是否正在加载相册视频
    @State private var isLoadingAllVideos = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 内容区域：空状态或任务列表
                content

                // 底部操作栏
                bottomBar
            }
            .navigationTitle("视频转 Live Photo")
            .toolbar {
                // 左侧：设置按钮
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }

                // 右侧：添加视频 + 清空按钮
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 手动选择视频
                    Button {
                        activeSheet = .picker
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.isConverting)

                    // 清空列表
                    if !viewModel.tasks.isEmpty && !viewModel.isConverting {
                        Button {
                            viewModel.clearTasks()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .picker:
                    PhotoPicker { assets in
                        viewModel.addTasks(assets: assets)
                        activeSheet = nil
                    }
                case .settings:
                    SettingsView(settings: viewModel.settings)
                case .progress:
                    BatchProgressView()
                }
            }
            .overlay {
                if isLoadingAllVideos {
                    ProgressView("正在加载相册视频...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                }
            }
            .alert("错误", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - 内容区域

    @ViewBuilder
    private var content: some View {
        if viewModel.tasks.isEmpty {
            emptyState
        } else {
            taskList
        }
    }

    /// 空状态提示
    /// 包含两个明显的操作按钮：一键全选 和 手动选择
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("选择要转换的视频")
                .font(.headline)
                .foregroundStyle(.secondary)

            // 一键全选按钮（大号醒目按钮）
            Button {
                loadAllVideos()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("一键全选相册视频")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingAllVideos)
            .padding(.horizontal, 40)

            // 手动选择按钮
            Button {
                activeSheet = .picker
            } label: {
                HStack {
                    Image(systemName: "hand.tap")
                    Text("手动选择视频")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingAllVideos)
            .padding(.horizontal, 40)

            Text("Live Photo 将保存到系统相册")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 任务列表
    private var taskList: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TaskRowView(task: task)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.removeTask(id: viewModel.tasks[index].id)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 底部操作栏

    /// 底部固定操作区域
    /// - 任务非空且未转换时显示"开始转换"
    /// - 转换中显示"取消"
    @ViewBuilder
    private var bottomBar: some View {
        if !viewModel.tasks.isEmpty {
            Divider()

            Group {
                if viewModel.isConverting {
                    // 转换中：取消按钮
                    Button {
                        viewModel.cancelConversion()
                    } label: {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    // 待转换：开始转换按钮
                    Button {
                        viewModel.startConversion()
                        activeSheet = .progress
                    } label: {
                        Text("开始转换 (\(viewModel.tasks.count) 个视频)")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    // MARK: - 一键全选

    /// 加载相册中所有视频
    /// 使用 PHAsset.fetchAssets 查询相册中的所有视频资源
    private func loadAllVideos() {
        isLoadingAllVideos = true

        Task {
            // 先请求相册权限
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            guard status == .authorized || status == .limited else {
                await MainActor.run {
                    isLoadingAllVideos = false
                    viewModel.errorMessage = "需要相册权限才能选择视频，请在设置中允许访问"
                }
                return
            }

            // 查询相册中所有视频
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            let count = fetchResult.count

            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            // 在主线程添加任务
            await MainActor.run {
                if assets.isEmpty {
                    viewModel.errorMessage = "相册中没有找到视频"
                } else {
                    viewModel.addTasks(assets: assets)
                }
                isLoadingAllVideos = false
            }
        }
    }
}

// MARK: - Sheet 类型

/// 当前激活的 sheet 类型，用于驱动 `.sheet(item:)`
enum ActiveSheet: Identifiable {
    case picker
    case settings
    case progress

    var id: String {
        switch self {
        case .picker: return "picker"
        case .settings: return "settings"
        case .progress: return "progress"
        }
    }
}

// MARK: - PHPicker 包装器

/// 使用 `UIViewControllerRepresentable` 包装 `PHPickerViewController`
///
/// 配置为仅显示视频（`.videos`），选择数量无限制（`selectionLimit = 0`）。
/// 选择完成后通过 `onPicked` 回调返回 `[PHAsset]` 数组。
struct PhotoPicker: UIViewControllerRepresentable {

    /// 选择完成回调，返回选中的 PHAsset 数组
    let onPicked: ([PHAsset]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .videos          // 仅显示视频
        configuration.selectionLimit = 0        // 0 表示无限制多选
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // 无需更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    /// PHPicker 代理协调器
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        /// 选择完成回调
        let onPicked: ([PHAsset]) -> Void

        init(onPicked: @escaping ([PHAsset]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // 关闭选择器
            picker.dismiss(animated: true)

            // 从选择结果中提取资源标识符
            let identifiers = results.compactMap { $0.assetIdentifier }
            guard !identifiers.isEmpty else {
                onPicked([])
                return
            }

            // 通过标识符从相册获取对应的 PHAsset
            let fetchResult = PHAsset.fetchAssets(
                withLocalIdentifiers: identifiers,
                options: nil
            )
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            onPicked(assets)
        }
    }
}

// MARK: - 预览

#Preview {
    VideoPickerView()
        .environmentObject(BatchViewModel())
}
