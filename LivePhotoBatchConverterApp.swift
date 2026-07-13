import SwiftUI

/// Live Photo 批量转换器 - 应用入口
/// 负责初始化全局状态并通过环境对象注入到视图层级中
@main
struct LivePhotoBatchConverterApp: App {
    /// 批量转换视图模型，在整个应用生命周期内保持单例
    @StateObject private var batchViewModel = BatchViewModel()

    var body: some Scene {
        WindowGroup {
            VideoPickerView()
                .environmentObject(batchViewModel)
        }
    }
}
