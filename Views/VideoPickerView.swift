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

                // 右侧：全选视频 + 添加视频 + 清空按钮
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 一键全选相册视频
                    Button {
                        loadAllVideos()
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .disabled(viewModel.isConverting || isLoadingAllVideos)

                    // 手动选择视频
                    Button {
                        activeSheet = .picker
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.isConverting)

                    // 清空列表
                    Button {
                        viewModel.clearTasks()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.tasks.isEmpty || viewModel.isConverting)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .picker:
                    // 视频选择器
                    PhotoPicker { assets in
                        viewModel.addTasks(assets: assets)
                        activeSheet = nil
                    }
                case .settings:
                    // 设置页
                    SettingsView(settings: viewModel.settings)
                case .progress:
                    // 批量进度页
                    BatchProgressView()
                }
            }
            .onChange(of: viewModel.isConverting) { converting in
                // 转换结束后自动关闭进度页
                if !converting, activeSheet == .progress {
                    activeSheet = nil
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
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("点击右上角选择视频")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("或点击 ✓ 一键全选相册视频")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .picker
        }
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
                isLoadingAllVideos = false
                return
            }

            // 查询相册中所有视频
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)

            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            // 在主线程添加任务
            await MainActor.run {
                viewModel.addTasks(assets: assets)
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
