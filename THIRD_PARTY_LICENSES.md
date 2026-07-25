# 第三方依赖许可证

**项目：** 无印字节  
**最后更新：** 2026 年 07 月 24 日  
**项目仓库：** https://github.com/chawu691/bytedance-nomark

---

## 项目自身许可证

无印字节自身源代码依照 **GNU General Public License Version 3（GPL-3.0）** 发布。

完整许可证文本见项目根目录的 `LICENSE` 文件。

---

## 直接依赖清单

| 组件 | 版本 | 用途 | 许可证 | 版权所有者 | 官方来源 |
|------|------|------|--------|-----------|----------|
| dio | 5.7.0 | HTTP 网络请求 | MIT | wendux | https://pub.dev/packages/dio |
| flutter_riverpod | 2.6.1 | 状态管理 | MIT | Remi Rousselet | https://pub.dev/packages/flutter_riverpod |
| gal | 2.3.2 | 保存图片/视频到相册 | MIT | nimask | https://pub.dev/packages/gal |
| shared_preferences | 2.3.2 | 本地键值持久化 | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/shared_preferences |
| path_provider | 2.1.4 | 平台缓存目录 | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/path_provider |
| flutter_svg | 2.0.10+1 | SVG 图标渲染 | MIT | dnfield | https://pub.dev/packages/flutter_svg |
| video_player | 2.9.2 | 视频播放 | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/video_player |
| cupertino_icons | 1.0.8 | iOS 风格图标 | MIT | Flutter Authors | https://pub.dev/packages/cupertino_icons |
| flutter_markdown | 0.7.3+1 | Markdown 渲染 | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/flutter_markdown |
| url_launcher | 6.3.0 | 打开外部链接 | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/url_launcher |
| pointycastle | 3.9.1 | SM3/MD5/SHA256 哈希（抖音 a_bogus 与 TikTok XBogus 签名） | MIT | Adi Nistor & Contributors | https://pub.dev/packages/pointycastle |
| share_plus | ^10.1.2 | 音乐文件分享（移动端 share sheet） | BSD-3-Clause | Flutter Authors | https://pub.dev/packages/share_plus |
| file_picker | ^8.1.3 | 桌面端 saveAs 对话框（音乐保存） | MIT | Miguel Higuera & Contributors | https://pub.dev/packages/file_picker |

---

## 算法移植声明

本应用在 `lib/services/abogus.dart` 与 `lib/services/xbogus.dart` 中实现了抖音 Web API 的 `a_bogus` 签名与 TikTok Web API 的 `X-Bogus` 签名。

上述两份算法的原始实现来自开源项目 **[Douyin_TikTok_Download_API](https://github.com/Evil0ctal/Douyin_TikTok_Download_API)**（作者：Evil0ctal），依照 **Apache License 2.0** 授权。本应用在遵循该许可证的前提下，将其中的 Python 实现移植为 Dart 版本，并保持算法行为一致。

- 原始版权所有者：Copyright (C) 2021 Evil0ctal
- 原始许可证：Apache-2.0
- 修改说明：将 Python 中的 RC4、SM3、MD5 等调用替换为 `pointycastle` 提供的等价实现；接口签名调整为适应 Flutter 异步网络栈。

完整 Apache-2.0 许可证文本见 https://www.apache.org/licenses/LICENSE-2.0。

---

## 联系方式

如发现遗漏、错误或许可证不兼容问题，请通过以下方式报告：

**联系邮箱：** lxuan2297@gmail.com  
**项目仓库：** https://github.com/chawu691/bytedance-nomark  
**Issue 地址：** https://github.com/chawu691/bytedance-nomark/issues