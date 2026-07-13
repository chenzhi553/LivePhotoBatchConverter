import SwiftUI

/// 设置页
///
/// 配置视频转 Live Photo 的各项参数：
/// - 封面帧位置（起始帧 / 中间帧 / 自定义时间）
/// - 视频时长裁剪（开关 + 3秒/5秒/10秒）
/// - 输出质量（标准 / 高质量）
/// - 关于信息（版本号、使用说明）
struct SettingsView: View {

    /// 用户设置（由上层传入，修改会实时生效）
    @ObservedObject var settings: LivePhotoSettings

    /// 用于关闭当前页面
    @Environment(\.dismiss) private var dismiss

    /// 自定义封面帧时间的输入文本
    @State private var customTimeText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 封面帧位置
                Section {
                    Picker("封面帧位置", selection: coverFrameSelection) {
                        Text("起始帧").tag(0)
                        Text("中间帧").tag(1)
                        Text("自定义").tag(2)
                    }

                    // 选择"自定义"时显示时间输入框
                    if case .custom = settings.coverFramePosition {
                        HStack {
                            Text("时间（秒）")
                            TextField("请输入秒数", text: $customTimeText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: customTimeText) { newValue in
                                    // 仅当输入可转为合法非负数字时才更新
                                    if let time = Double(newValue), time >= 0 {
                                        settings.coverFramePosition = .custom(time)
                                    }
                                }
                        }
                    }
                } header: {
                    Text("封面帧位置")
                } footer: {
                    Text("选择从视频中截取哪一帧作为 Live Photo 的静态封面图。")
                }

                // MARK: 视频时长裁剪
                Section {
                    Toggle("启用时长裁剪", isOn: durationToggleBinding)

                    // 启用裁剪时显示时长选择
                    if settings.maxVideoDuration != nil {
                        Picker("最大时长", selection: durationSelection) {
                            Text("3 秒").tag(TimeInterval(3))
                            Text("5 秒").tag(TimeInterval(5))
                            Text("10 秒").tag(TimeInterval(10))
                        }
                    }
                } header: {
                    Text("视频时长裁剪")
                } footer: {
                    Text("开启后会将视频裁剪至指定时长，关闭则保留原始时长。")
                }

                // MARK: 输出质量
                Section("输出质量") {
                    Picker("质量", selection: $settings.outputQuality) {
                        ForEach(OutputQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                }

                // MARK: 关于
                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("使用说明：选择视频后点击"开始转换"，转换完成的 Live Photo 将自动保存到相册。封面图位置与视频时长可在上方设置中调整。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                syncCustomTimeText()
            }
        }
    }

    // MARK: - 计算绑定

    /// 封面帧位置 Picker 的选中绑定
    /// 将 `CoverFramePosition` 枚举映射为 Int，便于 Picker 选择
    private var coverFrameSelection: Binding<Int> {
        Binding(
            get: {
                switch settings.coverFramePosition {
                case .beginning: return 0
                case .middle: return 1
                case .custom: return 2
                }
            },
            set: { newValue in
                switch newValue {
                case 0:
                    settings.coverFramePosition = .beginning
                case 1:
                    settings.coverFramePosition = .middle
                case 2:
                    // 切换到自定义时，保留已有时间或默认为 0
                    if case .custom(let t) = settings.coverFramePosition {
                        settings.coverFramePosition = .custom(t)
                        customTimeText = String(t)
                    } else {
                        settings.coverFramePosition = .custom(0)
                        customTimeText = "0"
                    }
                default:
                    break
                }
            }
        )
    }

    /// 时长裁剪开关绑定
    /// 开启时设置默认 3 秒，关闭时置为 nil（不裁剪）
    private var durationToggleBinding: Binding<Bool> {
        Binding(
            get: { settings.maxVideoDuration != nil },
            set: { enabled in
                if enabled {
                    if settings.maxVideoDuration == nil {
                        settings.maxVideoDuration = 3
                    }
                } else {
                    settings.maxVideoDuration = nil
                }
            }
        )
    }

    /// 时长选择 Picker 绑定
    private var durationSelection: Binding<TimeInterval> {
        Binding(
            get: { settings.maxVideoDuration ?? 3 },
            set: { settings.maxVideoDuration = $0 }
        )
    }

    // MARK: - 私有方法

    /// 同步自定义时间文本（页面出现时调用）
    private func syncCustomTimeText() {
        if case .custom(let t) = settings.coverFramePosition {
            customTimeText = String(t)
        }
    }
}

// MARK: - 预览

#Preview {
    SettingsView(settings: LivePhotoSettings())
}
