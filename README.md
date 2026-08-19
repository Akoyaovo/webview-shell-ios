# WebView Shell iOS

把任何网站打包成 iOS app。不需要 Mac，不需要 $99 开发者账号。

GitHub Actions 在云端编译，产出无签名 IPA，用第三方签名工具（全能签、TrollStore 等）装到手机上。前端改完刷新即生效，不用重新打包。

## 快速开始

1. **Fork 这个仓库**（必须是 public，否则 macOS runner 按 10x 计费）

2. **改两个地方**：
   - `Sources/WebViewController.swift` 第 6 行 → 你的网站地址
   - `Resources/Info.plist` 里的 `WKAppBoundDomains` → 你的域名

3. **Push 或手动触发 Actions** → 自动编译 → Artifacts 里下载 IPA

4. **发版本**：打 tag 会自动发 Release，直链可以直接喂给签名工具
   ```bash
   git tag v1.0 && git push --tags
   ```

## 它帮你处理好的坑

这些全是实际踩过的，不处理的话表现都是「看着没报错但就是不对」：

| 问题 | 表现 | 处理 |
|------|------|------|
| WKWebView 默认不跑 Service Worker | 每次冷启动全量走网络，比 PWA 还慢 | App-Bound Domains + `limitsNavigationsToAppBoundDomains` |
| WKWebView 不实现 JS 弹窗 | `alert()` 静默丢弃，`confirm()` 直接返回 `false` | 实现 `WKUIDelegate` 三个方法 |
| 渲染进程被系统回收 | 从后台切回来白屏，点什么都没反应 | `webViewWebContentProcessDidTerminate` 里重新加载 |
| `contentInsetAdjustmentBehavior` 默认值 | 网页内容被系统自动加 inset，顶部/底部留白 | 设成 `.never`，让网页自己用 `env(safe-area-inset-*)` |
| 回弹露出底色 | 上拉/下拉回弹时露出白色或灰色底 | `underPageBackgroundColor` 跟着 `<meta name="theme-color">` 走 |
| 外链把壳导航走了 | 点了个外部链接，整个 app 变成别的网站，回不来 | `decidePolicyFor` 里拦截，外链交给系统浏览器 |
| 无签名构建报 "requires a development team" | CI 编译直接失败 | `CODE_SIGN_IDENTITY` / `CODE_SIGNING_REQUIRED` / `CODE_SIGNING_ALLOWED` / `CODE_SIGN_ENTITLEMENTS` 四个全关 |
| workflow 里 tag push 不触发 | 打了 tag 但 Release 步骤永远不执行 | `on.push` 里要同时写 `branches` 和 `tags`；不能加 `paths` 过滤 |
| `GITHUB_TOKEN` 默认只读 | 发 Release 报 403 | workflow 里显式写 `permissions: contents: write` |

## 前端怎么配合

壳会在页面加载前注入两个全局变量：

```javascript
window.__NATIVE_SHELL__    // true（只在壳里存在）
window.__SHELL_VER__       // "1.0"（跟 project.yml 里的版本号一致）
```

用它来做壳内特殊逻辑（比如只在壳里追加 `viewport-fit=cover`）：

```javascript
if (window.__NATIVE_SHELL__) {
    // 壳里的逻辑
}
```

### viewport-fit=cover

PWA/浏览器里 iOS 会帮你把页面缩进安全区；壳里没人帮你缩（WebView 铺满整屏），所以需要你自己用 `env(safe-area-inset-*)` 让位。建议只在壳里动态追加：

```javascript
if (window.__NATIVE_SHELL__) {
    document.querySelector('meta[name="viewport"]')
        .content += ', viewport-fit=cover';
}
```

### 状态栏颜色

壳会读 `<meta name="theme-color">` 自动决定状态栏文字黑/白。你的网页切主题时改这个 meta 就行：

```javascript
document.querySelector('meta[name="theme-color"]').content = '#1a1a1a';
// 状态栏文字自动变白
```

## 推送通知

WKWebView 里 **收不到 Web Push**（这是 iOS 的限制，不是 bug）。Web Push 只给「加到主屏幕的 PWA」。

三个方案：

1. **PWA 并存**（最简单）：壳和 PWA 两个图标都留着，推送走 PWA 那边收。用户看到通知横幅，自己点壳的图标进去

2. **[Bark](https://github.com/Finb/Bark)**（不想用 PWA 推送的话）：装 Bark app，拿到设备 key，服务端一行 HTTP 就能推。系统级通知，跟壳/PWA 无关
   ```
   GET https://api.day.app/你的key/标题/内容
   ```

3. **APNs**（要 $99 开发者账号）：壳里写原生推送注册，服务端双发 Web Push + APNs

## 自定义

### 改 app 名称

- `project.yml` → `name` 和 `PRODUCT_NAME`
- `Resources/Info.plist` → `CFBundleDisplayName`
- `.github/workflows/build-ipa.yml` → 所有 `WebViewShell` 替换成你的名字

### 改图标

把 1024x1024 的图标放到 `Resources/Assets.xcassets/AppIcon.appiconset/`。注意 **不能带 alpha 通道**，否则编译直接报错。

### 版本号

`project.yml` 里的 `MARKETING_VERSION` 跟着 git tag 一起抬。版本号会进 UA，方便服务端日志区分用户装的是哪一版。

## 本地开发（可选，不是必须）

```bash
brew install xcodegen
xcodegen generate
open WebViewShell.xcodeproj
```

## License

MIT
