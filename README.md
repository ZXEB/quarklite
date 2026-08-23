# Quarklite

夸克网盘不限速下载工具（Android / Windows / iOS）。Android 与 Windows 使用 [Gopeed](https://github.com/GopeedLab/gopeed)，iOS 使用基于 URLSession 的原生后台下载器，支持：

- 夸克网盘扫码登录 / Cookie 登录
- 网盘文件浏览、搜索（支持 AI 识别内容搜索，可直接搜照片内容词）
- 相册：自动扫描网盘内全部照片，网格浏览、全屏查看、一键下载
- 分享链接解析（提取码自动识别）、批量转存
- 批量下载（多选后一次加入队列）
- BT / 磁力链接下载（Android / Windows；iOS 暂不支持）
- **上传：多文件上传、文件夹上传（保持目录结构），实时查看进度/速度，支持取消与重试**

## 下载 APK

在 GitHub Actions 页面打开最新的构建（workflow run），下载 **quarklite-apk** 工件：

1. 打开仓库的 [Actions](https://github.com/zxeb/quarklite/actions) 页面
2. 点击最新一次成功的构建
3. 在 Artifacts 区域下载 `quarklite-apk`

## 工作原理

```
Flutter App (UI)
  ├── QuarkApi (Dart)  → drive.quark.cn / pan.quark.cn 夸克接口
  │      └─ 登录、文件列表、搜索、下载直链、分享解析、转存
  │      └─ 上传：upload/pre 预申请 → update/hash 秒传 → OSS 分片直传 → 合并 → finish
  ├── Gopeed 内核（Android / Windows）
  │      └─ 本地 REST API (127.0.0.1) 多线程下载 / BT 磁力
  └── iOS URLSession 后台下载器
         └─ 原生 URLSession 后台下载 / 暂停恢复 / 任务持久化
```

- 夸克直链本身走 CDN 不限速，配合 Gopeed 多连接分片达到满速
- 下载时自动携带直链对应的 Cookie / Referer / User-Agent
- 会话 Cookie（`__puus`）每 100 分钟自动刷新，避免下载 403
- 相册使用夸克返回的缩略图地址加载，点击可全屏查看并下载原图
- 上传按服务端分片大小顺序直传 OSS，先算 MD5/SHA1 走秒传校验；
  上传页实时显示进度、速度与状态，支持取消 / 重试 / 清除已完成

## 本地构建

```bash
# 1. 编译 Gopeed 内核（需要 Go + Android SDK）
bash scripts/build_libgopeed.sh

# 2. 构建 APK
flutter pub get
flutter build apk --release
```


### iOS

- 最低系统版本为 iOS 15。
- 下载文件保存在应用 Documents/Quarklite，可在“文件 → 我的 iPhone → Quarklite”中查看。
- 首次在 macOS 构建前运行 `flutter pub get` 和 `cd ios && pod install`，并在 Xcode 中配置自己的签名团队。
- iOS 使用原生后台直链下载，不支持 BT / 磁力链接。

## 许可

本项目基于 **GPL-3.0** 协议开源。内嵌的 Gopeed 下载引擎同样为 GPL-3.0。
商用前请确认 Gopeed 的商业授权要求。

> 夸克网盘接口为社区逆向，可能随官方更新失效，请合理使用。
