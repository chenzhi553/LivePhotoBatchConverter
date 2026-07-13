# LivePhotoBatchConverter

## 项目简介

LivePhotoBatchConverter 是一款 iOS 应用，用于将相册中的视频批量转换为 Live Photo（实况照片）。用户只需从系统相册选择多个视频，应用会自动提取关键帧作为静态封面图，并将视频处理为符合 Apple Live Photo 标准的配对资源，一键保存到相册。

## 功能特性

- **批量转换**：支持一次性从相册选择多个视频，批量转换为 Live Photo
- **自动封面提取**：从视频中自动提取关键帧作为 Live Photo 的静态封面图，支持选择起始帧/中间帧/自定义时间点
- **视频时长裁剪**：可选将视频裁剪到 3/5/10 秒，适配 Live Photo 标准时长
- **元数据写入**：正确写入 Live Photo 所需的三条关键元数据（ContentIdentifier、MakerApple 17、StillImageTime），确保系统相册识别为原生 Live Photo
- **相册直接保存**：转换完成后自动保存到系统相册，无需额外导入步骤
- **实时进度跟踪**：显示每个转换任务的进度和状态，整体进度一目了然
- **转换完成通知**：批量转换完成后发送本地通知提醒
- **简洁界面**：采用 SwiftUI 原生设计风格，操作直观，适配 iPhone SE 小屏幕

## 技术栈

| 技术 | 说明 |
|------|------|
| **Swift 5.9** | 主开发语言 |
| **SwiftUI** | 声明式 UI 框架，构建全部界面 |
| **MVVM 架构** | Model-View-ViewModel 分层架构，逻辑与视图解耦 |
| **AVFoundation** | 视频处理、时长裁剪、帧提取 |
| **Photos Framework** | 与系统相册交互，保存 Live Photo |
| **ImageIO / CoreServices** | 图片元数据读写，写入 ContentIdentifier |
| **UniformTypeIdentifiers** | 统一类型标识，处理文件类型 |
| **XcodeGen** | 项目文件自动生成工具，基于 `project.yml` |

## 项目目录结构

```
LivePhotoBatchConverter/
├── project.yml                          # XcodeGen 项目配置文件
├── README.md                            # 项目说明文档
├── LivePhotoBatchConverterApp.swift     # App 入口文件
├── Models/                              # 数据模型层
│   ├── ConversionStatus.swift           #   转换状态枚举
│   ├── ConversionTask.swift             #   转换任务模型
│   └── LivePhotoSettings.swift          #   Live Photo 设置模型
├── Views/                               # 视图层（SwiftUI Views）
├── ViewModels/                          # 视图模型层
│   └── BatchViewModel.swift             #   批量转换 ViewModel
├── Services/                            # 服务层
│   ├── LivePhotoConverter.swift         #   Live Photo 核心转换服务
│   ├── MetadataWriter.swift             #   元数据写入服务
│   ├── PhotoLibraryManager.swift        #   相册管理服务
│   ├── TempFileManager.swift            #   临时文件管理
│   └── VideoProcessor.swift             #   视频处理服务
├── Utils/                               # 工具层
│   ├── Logger.swift                     #   日志工具
│   └── Extensions/                      #   Swift 扩展
│       ├── AVAsset+Extension.swift      #   AVAsset 扩展
│       └── CMTime+Extension.swift       #   CMTime 扩展
└── Resources/                           # 资源文件
    ├── Info.plist                       #   应用配置信息
    └── Assets.xcassets                  #   资源目录
        ├── Contents.json                #   资源根配置
        ├── AppIcon.appiconset/          #   App 图标
        │   └── Contents.json
        └── AccentColor.colorset/        #   强调色
            └── Contents.json
```

## 开发环境要求

| 项目 | 要求 |
|------|------|
| **操作系统** | macOS 13.0 或更高版本 |
| **Xcode** | Xcode 15.0 或更高版本 |
| **iOS 部署目标** | iOS 16.0 或更高版本 |
| **Swift** | 5.9 |
| **XcodeGen**（可选） | 2.0.0 或更高版本 |
| **测试设备** | 运行 iOS 16+ 的 iPhone（不支持模拟器测试 Live Photo 保存） |

### 安装 XcodeGen（可选）

如果希望通过 XcodeGen 自动生成 Xcode 项目文件，请先安装：

```bash
# 使用 Homebrew 安装
brew install xcodegen

# 或使用 Mint 安装
mint install yonaskolb/xcodegen
```

## 快速开始指南

### 方式一：使用 XcodeGen 生成项目（推荐）

1. 打开终端，进入项目根目录：

```bash
cd /path/to/LivePhotoBatchConverter
```

2. 运行 XcodeGen 生成 Xcode 项目：

```bash
xcodegen generate
```

3. 生成完成后，打开 `.xcodeproj` 文件：

```bash
open LivePhotoBatchConverter.xcodeproj
```

4. 在 Xcode 中选择你的开发团队（Signing & Capabilities），然后连接 iPhone 设备，点击运行（Cmd+R）即可。

### 方式二：手动在 Xcode 中创建项目

1. 打开 Xcode，选择 `Create a new Xcode project`
2. 选择 `iOS` → `App`，点击 Next
3. 填写项目信息：
   - **Product Name**: `LivePhotoBatchConverter`
   - **Bundle Identifier**: `com.livephoto.batchconverter`
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
   - **Minimum Deployments**: `iOS 16.0`
4. 创建项目后，将本目录下的所有源文件（`.swift`）、资源文件夹（`Models`、`Views`、`ViewModels`、`Services`、`Utils`、`Resources`）拖入项目中
5. 确保在项目设置中将 `Info.plist` 指向 `Resources/Info.plist`
6. 连接 iPhone 设备，点击运行

## 核心技术原理简介

Live Photo 是 Apple 在 iOS 9 中引入的功能，其本质是一张静态图片（JPEG）和一段短视频（MOV）的组合，通过特定的元数据将两者关联起来。

### Live Photo 的组成结构

```
Live Photo
├── 静态图片（JPEG）
│   └── 元数据 ContentIdentifier: "唯一标识符-UUID"
└── 视频文件（MOV）
    └── 元数据 ContentIdentifier: "唯一标识符-UUID"（与图片相同）
    └── 元数据 StillImageTime: 对应图片帧的时间点
```

### 关键技术点

1. **ContentIdentifier 配对**：JPEG 和 MOV 必须共享同一个 `ContentIdentifier`（UUID 格式），系统通过此标识将两者关联为 Live Photo

2. **StillImageTime 元数据**：MOV 文件中需要标记静态图片对应的帧时间点，通常设置为视频开始处（`0` 秒），这样系统在展示 Live Photo 时能正确定位封面帧

3. **视频格式要求**：
   - 视频时长建议在 3 秒左右（系统原生 Live Photo 时长约 3 秒）
   - 视频分辨率应与图片匹配
   - 需使用 H.264 编码，MOV 容器格式

4. **保存到相册**：使用 `PHAssetCreationRequest` 同时保存 JPEG 和 MOV，并指定 `ContentIdentifier`，系统会自动将其识别为 Live Photo

## 权限说明

应用运行需要以下系统权限：

| 权限 | Info.plist Key | 说明 |
|------|---------------|------|
| **相册读取** | `NSPhotoLibraryUsageDescription` | 读取相册中的图片和视频用于转换 |
| **相册写入** | `NSPhotoLibraryAddUsageDescription` | 将转换后的 Live Photo 保存到相册 |

> 注意：如果应用需要访问相册中特定相簿或进行更复杂的相册操作，可能需要申请完整的相册访问权限（`NSPhotoLibraryUsageDescription`）。仅保存照片到相册只需 `NSPhotoLibraryAddUsageDescription`。

## 部署指南

### 方式一：Windows 用户通过 GitHub Actions 云编译（推荐）

> 无需 Mac 电脑，全程在 Windows 上完成编译和安装。

#### 第 1 步：安装 Git

如果尚未安装 Git，从 [git-scm.com](https://git-scm.com/download/win) 下载安装。

#### 第 2 步：创建 GitHub 仓库

1. 注册/登录 [GitHub](https://github.com)
2. 点击右上角 `+` → `New repository`
3. 仓库名填 `LivePhotoBatchConverter`
4. 选择 **Public**（公开仓库可免费使用 GitHub Actions）
5. 勾选 `Add a README file`
6. 点击 `Create repository`

#### 第 3 步：上传代码到 GitHub

在项目目录（`LivePhotoBatchConverter` 文件夹）下打开 PowerShell 或 Git Bash：

```bash
# 初始化 Git 仓库
git init

# 添加所有文件
git add .

# 提交
git commit -m "初始化项目"

# 关联远程仓库（把下面的 URL 换成你自己的）
git remote add origin https://github.com/你的用户名/LivePhotoBatchConverter.git

# 推送
git branch -M main
git push -u origin main
```

#### 第 4 步：等待自动编译

1. 推送完成后，GitHub 会自动触发编译
2. 进入仓库页面 → 点击顶部 `Actions` 标签
3. 可以看到 `Build iOS IPA` 正在运行
4. 编译约需 5-10 分钟（首次可能稍慢）
5. 编译成功后，显示绿色对勾

#### 第 5 步：下载 IPA

1. 点击成功的编译记录
2. 页面底部 `Artifacts` 区域找到 `LivePhotoBatchConverter-ipa`
3. 点击下载，得到 `LivePhotoBatchConverter-ipa.zip`
4. 解压后得到 `LivePhotoBatchConverter.ipa` 文件

> **手动触发编译**：如果想重新编译，进入 `Actions` → `Build iOS IPA` → `Run workflow` → `Run workflow`

#### 第 6 步：通过爱思助手安装到 iPhone

1. 下载并安装 [爱思助手](https://www.i4.cn/)（PC 版）
2. 用数据线将 iPhone SE 连接至电脑
3. 打开爱思助手，等待设备识别
4. 进入「应用游戏」→「导入 IPA」，或直接拖拽 IPA 文件到爱思助手窗口
5. 爱思助手会提示输入 Apple ID 和密码进行免费签名
6. 签名完成后自动安装到设备

#### 第 7 步：信任开发者证书

1. 在 iPhone 上打开「设置」→「通用」→「VPN与设备管理」
2. 找到对应的开发者证书，点击「信任」
3. 之后即可正常打开应用

### 方式二：Mac 用户通过 Xcode 编译

1. 安装 XcodeGen：`brew install xcodegen`
2. 进入项目目录：`cd /path/to/LivePhotoBatchConverter`
3. 生成 Xcode 项目：`xcodegen generate`
4. 打开项目：`open LivePhotoBatchConverter.xcodeproj`
5. 在 Xcode 中选择 Apple ID 签名团队
6. 连接 iPhone，按 `Cmd+R` 编译运行
7. 或 `Product` → `Archive` 导出 IPA

## 常见问题

### Q1: 转换后的 Live Photo 在相册中只显示静态图片，没有动态效果？

**A**: 请检查以下几点：
- 确认 JPEG 和 MOV 的 `ContentIdentifier` 是否一致
- 确认 MOV 文件中是否正确写入了 `StillImageTime` 元数据
- 确认视频时长是否过长（建议 3-5 秒），过长的视频可能无法正常显示动态效果
- 在相册中长按照片查看是否有动态效果，某些 iOS 版本需要在照片上向上滑动查看

### Q2: 保存到相册时提示权限不足？

**A**: 请前往「设置」→「隐私」→「照片」，确认已授予应用相册访问权限。如果是首次使用，App 会弹出权限请求对话框，请选择允许。

### Q3: GitHub Actions 编译失败？

**A**: 常见原因：
- **仓库为 Private**：GitHub Actions 对私有仓库每月有免费时长限制（2000 分钟），公开仓库无限制。建议设为 Public
- **Xcode 版本不匹配**：workflow 中已配置自动选择最新 Xcode，如仍失败请查看 Actions 日志
- **XcodeGen 报错**：检查 `project.yml` 格式是否正确，所有引用的目录/文件是否存在

### Q4: XcodeGen 生成项目时报错？

**A**: 请确认：
- 已安装 XcodeGen（运行 `xcodegen --version` 检查）
- `project.yml` 文件格式正确（YAML 语法）
- 所有的 `sources` 路径指向的目录和文件确实存在

### Q5: 转换后的 Live Photo 封面帧不在期望的位置？

**A**: 请在设置页中调整封面帧位置：
- **起始帧**：取视频第 0 秒作为封面
- **中间帧**：取视频中点作为封面
- **自定义**：手动输入封面帧的时间点（秒）

### Q6: 在模拟器上无法测试 Live Photo 保存功能？

**A**: iOS 模拟器不支持完整的 Photos Framework 写入功能，Live Photo 的保存和预览必须在真机上测试。请使用运行 iOS 16+ 的 iPhone 进行测试。

### Q7: 免费签名的 App 过几天打不开了？

**A**: 这是 Apple 免费开发者证书的限制，免费签名有效期仅 7 天。7 天后需要重新通过爱思助手或 Xcode 签名安装。详见下方「注意事项」。

## 注意事项

1. **免费签名 7 天限制**
   - 使用免费 Apple ID 签名的 App 有效期仅为 **7 天**，过期后 App 将无法打开
   - 需要每隔 7 天重新通过 Xcode 或爱思助手进行签名安装
   - 每个免费 Apple ID 最多可同时签名 **3 个 App**
   - 如需长期使用，建议注册 Apple Developer Program（年费 $99 / ¥688）

2. **设备数量限制**
   - 免费 Apple ID 最多可绑定 3 台设备用于测试
   - 付费开发者账号最多可绑定 100 台设备

3. **Live Photo 时长建议**
   - 系统 Live Photo 标准时长约为 3 秒
   - 过长的视频会显著增加文件体积，建议裁剪到 3-5 秒

4. **文件大小**
   - Live Photo = JPEG + MOV，文件体积是单独图片的好几倍
   - 批量转换时请注意设备存储空间

5. **隐私安全**
   - 本应用不收集任何用户数据
   - 所有转换操作均在本地完成，不涉及网络传输
   - 临时文件会在转换完成后自动清理

6. **iOS 版本兼容性**
   - 最低支持 iOS 16.0
   - 部分旧版 iOS 可能无法正常显示 Live Photo 动态效果

7. **App 图标**
   - 当前项目仅包含图标配置文件（`Contents.json`），尚未配置实际图标图片
   - 如需自定义图标，请准备 1024x1024 像素的 PNG 图片，放置到 `Assets.xcassets/AppIcon.appiconset/` 目录中，并在 `Contents.json` 中引用

---

> 本项目仅供学习和个人使用，请勿用于商业用途。Live Photo 是 Apple Inc. 的商标。
