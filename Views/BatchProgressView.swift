import SwiftUI

/// 批量转换进度页
///
/// 在批量转换过程中展示整体进度与各任务明细：
/// - 顶部：整体进度条 + 百分比 + 已完成/总数
/// - 下方：任务列表，每行显示缩略图、文件名、时长、状态图标与进度条
struct BatchProgressView: View {

    /// 批量转换视图模型（通过环境注入）
    @EnvironmentObject private var viewModel: BatchViewModel

    /// 用于关闭当前页面
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 整体进度区域
                progressSection

                Divider()

                // 任务列表
                taskList
            }
            .navigationTitle("转换进度")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.isConverting {
                        // 转换中：显示取消按钮
                        Button("取消转换") {
                            viewModel.cancelConversion()
                        }
                        .tint(.red)
                    } else {
                        // 转换完成：显示完成按钮
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    // MARK: - 整体进度区域

    private var progressSection: some View {
        VStack(spacing: 8) {
            HStack {
                // 已完成 / 总数
                Text("\(completedCount)/\(viewModel.tasks.count) 已完成")
                    .font(.subheadline)

                Spacer()

                // 百分比
                Text("\(Int(viewModel.overallProgress * 100))%")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            // 整体进度条（使用系统 ProgressView）
            ProgressView(value: viewModel.overallProgress)
                .tint(.blue)
        }
        .padding()
    }

    // MARK: - 任务列表

    private var taskList: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TaskRowView(task: task)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - 计算属性

    /// 已完成的任务数量
    private var completedCount: Int {
        viewModel.tasks.filter { task in
            if case .completed = task.status { return true }
            return false
        }.count
    }
}

// MARK: - 预览

#Preview {
    BatchProgressView()
        .environmentObject(BatchViewModel())
}
