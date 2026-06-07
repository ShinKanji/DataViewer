# DataViewer

DataViewer 是一款面向 iPhone / iPad 的原生时序数据查看与分析应用，使用 SwiftUI 构建。可从本地导入 TXT / CSV 表格时序数据，在移动端完成信号浏览、曲线绘制、区间统计与信号运算，适合现场快速数据分析。

## 功能

- **数据导入**：支持 TXT / CSV，自动识别列头并加载时序通道
- **信号管理**：候选信号浏览、已选信号添加、拖放分组、多曲线同屏
- **曲线查看**：可缩放/平移视口、时间轴 scrubber、联动光标、可编辑可见时间窗
- **区间统计**：当前时间窗或 A/B 标记区间，输出各通道统计量；支持地理坐标摘要
- **信号计算**：倍率、求导、积分、滑动平均；批量去跳点（自动或手动阈值）

## 环境要求

- macOS + Xcode（iOS 17 SDK 或更高）
- 运行目标：**iPhone / iPad**（iOS 17.0+）

## 快速开始

1. 克隆仓库并在 Xcode 中打开 `DataViewer.xcodeproj`
2. 在 **Signing & Capabilities** 中为 `DataViewer` 选择你的 Development Team
3. 选择模拟器或真机，运行 `DataViewer` scheme

## 构建与测试

在项目根目录执行：

```bash
xcodebuild -scheme DataViewer \
  -destination 'platform=iOS Simulator,name=iPad (A16)' \
  build test
```

单元测试与 UI 测试依赖本地样例数据。请在项目根目录创建 `testdata/`（已在 `.gitignore` 中忽略），并放入 `sample_timeseries.txt`。Xcode Scheme 会通过 `TESTDATA_DIR=$(SRCROOT)/testdata` 传递给测试目标。

## 数据格式

- 文件扩展名：`.txt`、`.csv`
- 首行为列名；需包含时间列与至少一个数值列
- 大文件按列懒加载，适合较长时序

## 许可证

本项目采用 [Apache License 2.0](LICENSE) 发布。
