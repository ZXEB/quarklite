# 夸克极速 QuarkLite

夸克网盘不限速下载工具（Android）。内置 [Gopeed](https://github.com/GopeedLab/gopeed) 多线程下载引擎，支持：

- 夸克网盘扫码登录 / Cookie 登录
- 网盘文件浏览与一键下载（直链 + 多线程不限速）
- 分享链接解析（提取码自动识别）、转存到网盘
- BT / 磁力链接下载

## 下载 APK

在 GitHub Actions 页面打开最新的构建（workflow run），下载 **quarklite-apk** 工件：

1. 打开仓库的 [Actions](https://github.com/zxeb/quarklite/actions) 页面
2. 点击最新一次成功的构建
3. 在 Artifacts 区域下载 `quarklite-apk`

## 工作原理

```
Flutter App (UI)
  ├── QuarkApi (Dart)  → drive.quark.cn / pan.quark.cn 夸克接口
  │      └─ 登录、文件列表、下载直链、分享解析、转存
  └── Gopeed 内核 (libgopeed.aar, Go 编译)
         └─ 本地 REST API (127.0.0.1) 多线程下载 / BT 磁力
```

- 夸克直链本身走 CDN 不限速，配合 Gopeed 多连接分片达到满速
- 下载时自动携带直链对应的 Cookie / Referer / User-Agent
- 会话 Cookie（`__puus`）每 100 分钟自动刷新，避免下载 403

## 本地构建

```bash
# 1. 编译 Gopeed 内核（需要 Go + Android SDK）
bash scripts/build_libgopeed.sh

# 2. 构建 APK
flutter pub get
flutter build apk --release
```

## 许可

本项目基于 **GPL-3.0** 协议开源。内嵌的 Gopeed 下载引擎同样为 GPL-3.0。
商用前请确认 Gopeed 的商业授权要求。

> 夸克网盘接口为社区逆向，可能随官方更新失效，请合理使用。
