# 无印字节

豆包、抖音分享内容的无水印媒体解析与下载工具。

## 工具链

- 标准平台：Flutter 3.44，支持 Android、iOS 15+、Windows、macOS 和 Linux。
- HarmonyOS NEXT：OpenHarmony-SIG Flutter `3.22.1-ohos-0.1.0`、API 12+。
- Dart 兼容范围：`>=3.4.0 <4.0.0`。

标准平台使用 `flutter test` 和对应的 `flutter build` 命令。HarmonyOS 环境配置
DevEco Studio、API 12 SDK、匹配的 OHOS Flutter engine 及本地签名后，执行：

```shell
flutter pub get
flutter build hap --debug
```

发布签名和 Team ID 不提交到仓库，由各发布环境提供。
