# 迅雷云盘 API 逆向文档

> 逆向来源：AList 社区驱动（`drivers/thunder` / `drivers/thunder_browser` / `drivers/thunderx`，持续维护、大规模使用验证）+ 迅雷云盘前端（pan.xunlei.com Nuxt.js SPA）静态分析。
> 状态：2026-08 确认可用，接口可能随官方更新失效。

## 1. 接口总览

| 用途 | Base URL | 说明 |
|---|---|---|
| 云盘 API | `https://api-pan.xunlei.com/drive/v1` | 迅雷 App（com.xunlei.downloadprovider） |
| 云盘 API | `https://x-api-pan.xunlei.com/drive/v1` | 迅雷浏览器（com.xunlei.browser），API 结构相同 |
| 云盘 API | `https://api-pan.xunleix.com/drive/v1` | 迅雷X（com.thunder.downloader） |
| 账号体系 | `https://xluser-ssl.xunlei.com/v1` | 登录 / token / 验证码，三套共用（X 版为 xluser-ssl.xunleix.com） |
| 视频代理 | `https://web-vod-xdrive.xunlei.com/ts_downloader` | 网页播放器视频转 TS 下载代理 |

常用资源路径（相对 `drive/v1`）：

```
GET  /files                    文件列表（分页）
POST /files                    建文件夹 / 创建上传任务 / 离线下载
GET  /files/{file_id}          文件详情（含下载直链 web_content_link / 视频链接 medias）
PATCH /files/{file_id}         重命名
POST /files:batchMove          移动
POST /files:batchCopy          复制
PATCH /files/{file_id}/trash   删除到回收站
GET  /tasks                    离线下载任务列表
```

## 2. 认证流程（账号密码 + refresh_token 持久化）

推荐方案：首次账号密码登录拿 `access_token` + `refresh_token`，之后用 refresh_token 续期并持久化，避免重复触发风控。

### 2.1 获取验证码 token

```
POST https://xluser-ssl.xunlei.com/v1/shield/captcha/init
```

请求体：

```json
{
  "action": "POST:/v1/auth/signin",
  "captcha_token": "",
  "client_id": "<ClientID>",
  "device_id": "<32位hex>",
  "meta": {
    "phone_number": "手机号"     // 邮箱填 email，其他填 username
  },
  "redirect_uri": "xlaccsdk01://xunlei.com/callback?state=harbor"
}
```

响应：

```json
{
  "captcha_token": "xxx",
  "expires_in": 86400,
  "url": ""
}
```

- `captcha_token` 为空即成功；`url` 非空表示需要人工验证（见 2.5）
- `captcha_sign`：请求 `action` 对应的签名，由客户端算出后放进 `meta.timestamp` / `meta.captcha_sign`

### 2.2 captcha_sign 签名算法（MD5 链）

```
timestamp = 当前毫秒时间戳
str = ClientID + ClientVersion + PackageName + DeviceID + timestamp
for alg in Algorithms:
    str = md5hex(str + alg)
sign = "1." + str
```

三套客户端的 `Algorithms` 数组见第 4 节。这是纯算法，无随机因子，Dart 可直接实现。

### 2.3 账号密码登录

```
POST https://xluser-ssl.xunlei.com/v1/auth/signin
```

请求体（迅雷浏览器客户端，流程最简）：

```json
{
  "captcha_token": "<2.1拿到的>",
  "client_id": "<ClientID>",
  "client_secret": "<ClientSecret>",
  "username": "手机号/邮箱",
  "password": "明文密码"
}
```

响应 `TokenResp`：

```json
{
  "token_type": "Bearer",
  "access_token": "xxx",
  "refresh_token": "xxx",
  "expires_in": 604800,
  "sub": "<user_id>",
  "user_id": "<user_id>"
}
```

Authorization 头 = `Bearer <access_token>`。

### 2.4 refresh_token 续期

```
POST https://xluser-ssl.xunlei.com/v1/auth/token
```

请求体：

```json
{
  "grant_type": "refresh_token",
  "refresh_token": "<refresh_token>",
  "client_id": "<ClientID>",
  "client_secret": "<ClientSecret>"
}
```

响应同为 `TokenResp`。注意：服务端可能不轮换 refresh_token（响应里该字段为空），此时保留旧值即可。refresh_token 有效期较长，可跨重启恢复登录态。

### 2.5 风控人工验证（review_panel）

登录接口（含 captcha init）返回 `error: "review_panel"` 时表示触发风控：

- 响应里带 `creditkey` 和 `reviewurl`
- 需要用户打开 `https://i.xunlei.com/xlcaptcha/android.html`，控制台执行 `reviewCb({...reviewData})` 完成短信/智能检测
- 完成后拿到新的 `creditkey`，填入下次登录请求的 `creditkey` 字段
- 规避手段：refresh_token 持久化 + 固定 DeviceID，尽量避免重复全流程登录

## 3. 请求头规范

基础头（所有请求）：

```
user-agent:       <客户端 UA>
accept:           application/json;charset=UTF-8
x-device-id:      <DeviceID, 32位hex>
x-client-id:      <ClientID>
x-client-version: <ClientVersion>
```

登录后追加：

```
Authorization:    Bearer <access_token>
X-Captcha-Token:  <captcha_token>
```

错误码为 `4122 / 4121 / 10 / 16` 时 → token 过期，用 refresh_token 续期后重试；
错误码 `9`（`captcha_invalid`）时 → 重新走 2.1 拿验证码 token。

响应体（drive API）字段：

```json
{
  "error_code": 0,
  "error": "success",
  "error_description": ""
}
```

`error_code == 0` 或 `error == "success"` 即成功。

## 4. 三套客户端凭据

### 迅雷 App（默认推荐）

| 项 | 值 |
|---|---|
| ClientID | `Xp6vsxz_7IYVw2BB` |
| ClientSecret | `Xp6vsy4tN9toTVdMSpomVdXpRmES` |
| ClientVersion | `8.31.0.9726` |
| PackageName | `com.xunlei.downloadprovider` |
| APPID / APPKey（v3 登录用） | `40` / `34a062aaa22f906fca4fefe9fb3a3021` |
| UA | `ANDROID-com.xunlei.downloadprovider/8.31.0.9726 netWorkType/5G appid/40 deviceName/Xiaomi_M2004j7ac deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 (Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)` |
| 下载 UA | `Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)` |
| Algorithms | `9uJNVj/wLmdwKrJaVj/omlQ, Oz64Lp0GigmChHMf/6TNfxx7O9PyopcczMsnf, Eb+L7Ce+Ej48u, jKY0, ASr0zCl6v8W4aidjPK5KHd1Lq3t+vBFf41dqv5+fnOd, wQlozdg6r1qxh0eRmt3QgNXOvSZO6q/GXK, gmirk+ciAvIgA/cxUUCema47jr/YToixTT+Q6O, 5IiCoM9B1/788ntB, P07JH0h6qoM6TSUAK2aL9T5s2QBVeY9JWvalf, +oK0AN` |

### 迅雷浏览器（登录流程最简，可作登录首选）

| 项 | 值 |
|---|---|
| ClientID | `ZUBzD9J_XPXfn7f7` |
| ClientSecret | `yESVmHecEe6F0aou69vl-g` |
| ClientVersion | `1.10.0.2633` |
| PackageName | `com.xunlei.browser` |
| APPID / APPKey | `22062` / `a5d7416858147a4ab99573872ffccef8` |
| 下载 UA | `AndroidDownloadManager/13 (Linux; U; Android 13; M2004J7AC Build/SP1A.210812.016)` |
| Algorithms | `uWRwO7gPfdPB/0NfPtfQO+71, F93x+qPluYy6jdgNpq+lwdH1ap6WOM+nfz8/V, 0HbpxvpXFsBK5CoTKam, dQhzbhzFRcawnsZqRETT9AuPAJ+wTQso82mRv, SAH98AmLZLRa6DB2u68sGhyiDh15guJpXhBzI, unqfo7Z64Rie9RNHMOB, 7yxUdFADp3DOBvXdz0DPuKNVT35wqa5z0DEyEvf, RBG, ThTWPG5eC0UBqlbQ+04nZAptqGCdpv9o55A` |

### 迅雷X（com.thunder.downloader）

| 项 | 值 |
|---|---|
| ClientID | `ZQL_zwA4qhHcoe_2` |
| ClientSecret | `Og9Vr1L8Ee6bh0olFxFDRg` |
| ClientVersion | `1.06.0.2132` |
| API Base | `https://api-pan.xunleix.com/drive/v1` |
| 下载 UA | `Dalvik/2.1.0 (Linux; U; Android 13; M2004J7AC Build/SP1A.210812.016)` |

## 5. 文件列表

```
GET https://api-pan.xunlei.com/drive/v1/files
```

查询参数（迅雷 App）：

```
space:      ""
__type:     drive
refresh:    true
__sync:     true
parent_id:  0            ← 根目录为 "0"
page_token: ""           ← 翻页用 next_page_token
with_audit: true
limit:      100
filters:    {"phase":{"eq":"PHASE_TYPE_COMPLETE"},"trashed":{"eq":false}}
```

迅雷浏览器版附加参数：`with=url`、`thumbnail_size=SIZE_LARGE`。

响应：

```json
{
  "kind": "drive#fileList",
  "next_page_token": "xxx",
  "files": [
    {
      "kind": "drive#file",
      "id": "xxx",
      "parent_id": "0",
      "name": "文件名",
      "size": "12345678",
      "hash": "<gcid>",
      "thumbnail_link": "https://...",
      "icon_link": "https://...",
      "web_content_link": "https://...",   // 列表即可能携带
      "created_time": "2026-01-01T00:00:00Z",
      "modified_time": "2026-01-01T00:00:00Z",
      "trashed": false,
      "medias": [ ... ]
    }
  ]
}
```

- 目录 `kind == "drive#folder"`，文件 `kind == "drive#file"`；根目录 id 为 `"0"`
- `size` 是字符串，解析时注意转 int

## 6. 高速下载直链

```
GET https://api-pan.xunlei.com/drive/v1/files/{file_id}
```

迅雷浏览器版带参数：`_magic=2021&space=<space>&thumbnail_size=SIZE_LARGE&with=url`。

返回文件详情（结构同列表项），关键字段：

- **`web_content_link`**：HTTP 签名直链（CDN），形如
  `https://dcdnpc.sdpan.cn/xxx?e=<过期unix时间戳>&...`，下载唯一需要的数据
- **`medias[].link.url`**：视频流媒体链接，独立 CDN（`link.type` 区分用途）
- **`medias[].link.expire` / `medias[].link.token`**：过期时间 / 鉴权 token

前端另发现 `getFileInfo` 支持 `usage` 参数（`PLAY` / `CONSUME`），疑似影响返回链接类型，实现时建议对比验证。

### 下载请求

```
GET <web_content_link>
User-Agent: Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)
```

**关键点：UA 影响下载限速档位**（AList 元数据明确标注"不影响登录，影响下载速度"），必须用客户端下载 UA 而非浏览器 UA。

### 视频加速（视频文件专用）

1. 直接使用 `medias[].link.url`（流媒体 CDN，限速策略与下载 CDN 不同）
2. 或通过网页代理：`https://web-vod-xdrive.xunlei.com/ts_downloader?client_id=<ClientID>&url=<encodeURIComponent(media.link.url)>`

## 7. 错误码表

| error_code | 含义 | 处理 |
|---|---|---|
| 0 | 成功 | - |
| 4122 / 4121 / 10 / 16 | access_token 过期 | refresh_token 续期后重试 |
| 9 | 验证码 token 过期 / space_token 失效 | 重新 captcha init |
| - | `error: "review_panel"` | 触发风控，需人工验证（2.5） |

## 8. 限速机制分析（重要）

- **限速由账号等级决定**：免费用户直链被 CDN 限速（社区实测约 2~10MB/s，视节点与网络）；会员（VIP/SVIP）满速
- **迅雷官方"高速下载"= 会员通道 + 迅雷客户端 P2P 加速网络（专有 xl 协议，闭源）**：网页版"高速下载"按钮会弹下载引擎选择框（免费/VIP/SVIP），免费档即浏览器直下，VIP 档拉起迅雷客户端引擎
- **xl 协议无法逆向复刻**：没有成功开源先例，工程量是协议级逆向（数万行），本项目不做

### 可达成的提速手段（实现时内置）

1. **正确 UA**：用 `Dalvik/...` 或 `AndroidDownloadManager/...` 下载 UA（影响限速档位）
2. **多线程分片**：gopeed 16~32 连接（部分节点按单连接限速时可拉满）
3. **视频走媒体 CDN**：`medias[].link.url` 或 `ts_downloader` 代理
4. **链接过期重取**：解析 `web_content_link` 的 `e=` 参数，快过期时重新 `GET /files/{id}`；下载中 403 时同样重取（配合持久化 token）
5. **客户端切换兜底**：三套 client_id/UA 实测选最快

## 9. 实现要点（对照本仓库结构）

- 新建 `lib/api/xunlei_client.dart`：`XunLeiClient`（captcha init → signin → refresh_token → 列表 → 直链），结构对照 `quark_client.dart`
- `captcha_sign` 签名（MD5 链）与 `DeviceID`（`md5(账号+密码)` 或随机 32hex）为纯 Dart 实现
- token 持久化对照 `AppState` 的 cookie 双写（secure storage + SharedPreferences），存 `refresh_token`
- 下载走 `DownloadService` 现有 Gopeed 通道，headers 带下载 UA + Referer（`https://pan.xunlei.com/`），连接数建议 16~32
- 会话刷新定时器：access_token 有效期约 7 天（`expires_in`），用 refresh_token 自动续期；直链 `e=` 过期前重取

## 10. 参考来源

- AList：`drivers/thunder/{driver,util,types,meta}.go`（迅雷 App）
- AList：`drivers/thunder_browser/{driver,util}.go`（迅雷浏览器，登录最简）
- AList：`drivers/thunderx/{driver,util}.go`（迅雷X）
- pan.xunlei.com 前端 JS 静态分析：`getFileInfo(usage)`、`ts_downloader`、下载引擎弹窗
- AList PR #8342：账号密码登录修复 + creditkey 风控流程说明
