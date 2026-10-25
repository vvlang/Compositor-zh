# 维护这个本地化分支

> 这份文档写给维护 `vvlang/Compositor-zh` 的人。**普通用户不需要看**——
> 他们只看 README（安装、功能、Gatekeeper 放行）。

README 里刻意不写这些：构建怎么跑、提交怎么组织、怎么同步上游。
对用户是噪音；对维护者是每天都要用三遍的东西。

## 目录

- [构建与发布](#构建与发布)
- [同步上游](#同步上游)
- [汉化机制](#汉化机制)
- [提交历史](#提交历史)
- [这个 fork 改过上游什么](#这个-fork-改过上游什么)

---

## 构建与发布

### 本机构建

```sh
bash scripts/package-adhoc-dmg.sh      # → dist/Compositor-<版本>.dmg
```

**用 `bash` 调用，不要用 `./scripts/package-adhoc-dmg.sh`。** 这个仓库在云同步
目录里，同步客户端会清掉可执行位（git 里是 755，工作区会被重置成 600）。
仓库里已经有两次提交在修这个问题（`86d3378`、`988dc47`）。

ad-hoc 签名、无公证，代价是首次打开要手动放行一次（README 里有三种解法）。

### 自动化

推到 `main` 会自动触发 `.github/workflows/release.yml`：

| 触发 | 结果 |
|---|---|
| 推 `main` | 按 `MARKETING_VERSION` 发布/更新 `v<版本>` Release，同名附件 `--clobber` 覆盖 |
| 打 `v*` tag | 发布一个按 tag 命名的 Release |
| 手动 | 同推 main，只是由人触发 |
| 每天 8:00 | `Upstream watch` 检查上游有没有新提交，有就在 run summary 里报告 |

**每个版本一个 Release**。早先让 `latest` 持有附件，结果 `--clobber` 只覆盖同名
文件而附件名带版本号，每升一次版本就留下一个旧的（1.4.8 / 1.4.10 / 1.5.1 同时挂着）。
现在按版本分开，workflow 里一条 DELETE 都没有。

`latest` 那个 Release 是旧结构留下的，不再更新，可以删：

```sh
gh release delete latest --repo vvlang/Compositor-zh --yes
```

### CI 的三个 job

| Job | 查什么 |
|---|---|
| `unit` | 全部单元 + 窗口测试 |
| `localization` | `audit-localization.sh` + `translate-missing.py --check` |
| `screenshots` | 上游加的，截图存进 artifact |

`verify.yml` 是上游文件，本 fork 相对它**只多出 `localization` 这一个 job**，
上游的东西一行没动——这样下次合并冲突最小。

`localization` 必须用 macOS：目录靠 `xcstringstool` 提取，换 Linux 目录一致性
那步会直接报错，形状检查还在，等于只验了一半。

### 本机跑测试

CI 用的是 Xcode 26.6 + macos-26。本机直连 `xcodebuild test` 会挂在两处，
都不是代码问题：

| 症状 | 原因 | 怎么办 |
|---|---|---|
| `No signing certificate "Mac Development" found` | 本机没有开发证书 | 加 `CODE_SIGN_IDENTITY=-` |
| `Library not loaded: @rpath/Sparkle.framework`，`different Team IDs` | app 带了 hardened runtime，Sparkle 是另一份签名 | 加 `ENABLE_HARDENED_RUNTIME=NO`，构建后再 `codesign --force --deep --sign -` 一次（与 `package-adhoc-dmg.sh` 同一手） |

照 CI 的样子跑：

```sh
xcodebuild build-for-testing -project Compositor.xcodeproj -scheme Compositor \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO \
  GCC_OPTIMIZATION_LEVEL=s SWIFT_OPTIMIZATION_LEVEL=-O
codesign --force --deep --sign - <DerivedData>/Build/Products/Debug/Compositor.app
bash scripts/ci-tests.sh <DerivedData>
```

**DerivedData 不要放在这个仓库里**：它在云同步目录里，同步客户端会破坏
Sparkle.xcframework 里的符号链接，构建会报 `could not determine executable path`。
用默认位置（`~/Library/Developer/Xcode/DerivedData`）就好。

`ci-tests.sh` 一次开四个测试进程，四个都在 main actor 上跑，彼此抢 GPU。
本机偶尔会出现 `The test runner hung before establishing connection`（宿主没起来，
不是用例失败）或某条像素级断言偶发——**以 CI 为准**。

### 关于 Sparkle

`Config/Info.plist` 的 `SUFeedURL` 指向**上游**，`scripts/publish.sh` 的 `REPO`
也是上游。这是**有意为之**：中文版用户想跟进上游最新功能时，Sparkle 会把他们
带去装英文上游版，正是他们需要的。

代价是中文版自己做不了 Sparkle 自动更新——`SUPublicEDKey` 是上游的 EdDSA 公钥，
私钥在他手里，而且你的构建是 ad-hoc 签名，Sparkle 本来也不接受。

**推上游在结构上不可能**：`upstream` 的 push URL 是 `DISABLED://never-push-to-upstream`。

---

## 同步上游

### 流程

```sh
git fetch upstream
git checkout main && git pull --ff-only
git merge --no-ff upstream/main
```

上游的 `upstream` 标签会一起被 fetch 过来，**不要 `git push --tags`**——
那会把上游的 tag 推到你的仓库。

### 冲突怎么处理

冲突的根因不是逻辑打架，而是**同一行做了不同的事**：上游改了功能结构，
我们把同一行包进了 `L10n`。

```sh
git diff --name-only --diff-filter=U
git checkout --theirs <文件>     # 一律以上游为准
```

然后**把 L10n 包装重新贴回去**。保住功能比保住几处译文重要得多——代价只是
那几处界面显示英文。

L10n 那套「显示值与身份值分离」的改造（见下节）确实有效：1.5.1 那次合并
只有 2 个文件冲突，而 1.4.10 那次有 11 个。

### 合并后必跑

```sh
python3 scripts/gen-xcstrings.py       # 重新生成目录，报出待翻译条目
bash    scripts/audit-localization.sh   # 形状检查 + 目录一致性
python3 scripts/translate-missing.py --check   # 占位符完整性
xcodebuild -project Compositor.xcodeproj -scheme Compositor \
           -destination 'platform=macOS' test
```

**新文案不会让编译变红。** 漏翻的键只是静默显示英文，跑测试也发现不了——
只有审计脚本能抓到。

### 上游新测试常常假设英文

合并后跑测试时，如果上游新加的测试红了，多半是它硬编码了英文：

- 比对撤销名 → 改成 `L10n.string("...")`（本仓库既有写法，撤销名是读取时才查目录的）
- 比对 tab 标题 / 工程名 → 同上
- 写死像素阈值 → 改成按视图自身宽度判断，「未命名 2」比 "Untitled 2" 宽

**macOS 返回的 ICC 描述文件名是本地化的**：中文系统上 "Generic CMYK Profile"
查不到，返回的是「普通CMYK描述文件」。测试别断言英文名。

---

## 汉化机制

### 一条铁律

> **英文字符串永远不能进入「被比较」或「被持久化」的位置。**

只有显示路径才本地化。任何参与相等比较、当字典键、或者写进 `.comp` / manifest /
`UserDefaults` 的字符串，一律保持英文。

违反它**不会崩溃**，只会**静默失效**——这是最难查的一类 bug。

涉及的持久化标识符：混合模式 `blendMode`、调整类型 `adjustment.kind`、
曲线/色阶通道、`transform.sampling`、HSV 区间（同时也是 JSON 字典键）、
文本对齐。

### 三处「显示值与身份值分离」

这些是纯重构、不改行为，本地化并不依赖它们（上游可以拒绝）：

| 位置 | 改前 | 改后 |
|---|---|---|
| `UI/BlendModePicker.swift` | `NSMenuItem(title: rawValue)`，再用 `title` 反查枚举 | 身份移到 `representedObject`；标题用 `localizedName` |
| `UI/KeyboardShortcuts.swift` | `id = "\(group):\(title)"`，`group` 还参与逻辑比较 | `id` 和比较保持英文；新增 `displayTitle` / `displayGroup` |
| `Document/DocumentHistory.swift` | `beginEdit(_ name: String)` | 参数改成 `String.LocalizationValue`；撤销名读取时解析 |

### 工具

```sh
python3 scripts/gen-xcstrings.py            # 重新生成目录
python3 scripts/gen-xcstrings.py --check    # 只报告（CI 用）
bash    scripts/audit-localization.sh       # 形状检查 + 目录一致性
python3 scripts/translate-missing.py --check  # 占位符完整性，不需要密钥
python3 scripts/translate-missing.py        # 翻译缺失的（需要 MINIMAX_API_KEY）
```

**目录一致性只查「键在不在、译了没译」**，查不出占位符个数或顺序被改坏——
那类错误界面上不崩溃，只是显示错，所以 `translate-missing.py --check` 是独立的。

### 占位符

两种写法等价：文件里存 `%arg`（可移植），目录和运行时是 `%@`。
**写文件时用 `%arg`**——写成 `%@` 会造成键对不上，译文看起来存在却永远匹配不到。

校验规则来自对现有译文的实测，不是猜的：

- 占位符个数必须相等
- **顺序必须一致**（`String(format:)` 按位置取值，重排会静默装反）
- 译文非空、不等于原文、无残缺的 `%arg`

### 插值的类型决定键

目录里的键就是**运行时真正查找的那个字符串**，所以插值的类型不能随便：

| 插值 | 运行时键 | 目录里存的 |
|---|---|---|
| `\(String(x))` | `%@` | `%@` ✓ |
| `\(Int(x))` | `%lld` | `%@` ✗ |

`xcstringstool` 一律把插值提取成 `%arg`（脚本再换成 `%@`），但 `String(localized:)`
和 SwiftUI 的 `LocalizedStringKey` 在运行时是**按插值的类型**拼键的：Int 插值得到
`%lld`。目录里没有这个键，查表落空，界面静默显示英文——不报错、不崩溃，
审计脚本也发现不了（它只查「键在不在、译了没译」）。

所以**凡是插进键里的值，一律先包成 `String(...)`**：

```swift
L10n.string("\(String(Int(delay.rounded())))ms")     // 键 %@ms，目录里有
L10n.string("\(Int(delay.rounded()))ms")             // 键 %lldms，永远查不到
```

上游的 SwiftUI 字面量（`Text("\(Int(x)) px")`）踩的是同一个坑：它们不是 `L10n`
调用，目录里同样只有 `%@` 版本。要让它们翻译，得把插值也包成 `String(...)`。

### 「不需要翻译」的判据

不能靠「长得像不像缩写」判断。`RGB` 该保持原样，但 `Navigator`、`Format`、
`Filter` 长得也像缩写，却是货真价实的界面文案，按启发式会漏译。

只认两类明确的记号：全部是数字或标点（`100%`、`2 × 2`），或是已知单位/格式/
按键名（`px`、`JPEG`、`Esc`）。其余一律送去翻译——宁可多译几个词，不能漏译。

完整名单在 `scripts/gen-xcstrings.py` 的 `VERBATIM_OK`，
以及 `CompositorTests/LocalizationTests.swift` 的 `verbatimKeys`（两处都要改）。

---

## 提交历史

工作拆成了主题化的提交，上游可以只 cherry-pick 想要的，或者整组回退：

```
b187379  prepare for localization without changing behavior   ← 纯重构，对上游友好
b6250d3  route display sites through the catalog
ba82f1d  localize the interface in Simplified Chinese         ← 主体
dc2ddca  catch the strings the first pass missed
15786f8  translate documentation to Simplified Chinese
```

### 注释汉化

`EditorSession.swift`（98 条）和 `EditorCanvas.swift`（326 条）的中文注释在
1.4.10 那次同步时随上游重写回到了英文。它们恰好是和上游冲突最狠的两个文件
（`EditorCanvas.swift` 一个就改了 677 行），而注释在运行时不产生任何作用——
等于让每次同步的冲突面翻倍。

要恢复的话另开一轮，别在上游还在改这些文件的时候追着改。

回退到「中文界面 + 英文注释」的版本：revert 掉 `4d81eb5` 之上那个 `--no-ff`
合并提交。它是独立的一个 commit，回退不碰汉化本身。`l10n-comments` 分支还在。

### 每次同步的教训

- **2026-10-10（1.4.10）**：11 个冲突。上游为 16 位图层加了字段和参数，
  我们把同一行包进 L10n。代码取上游，汉化重新贴。
- **2026-10-13（1.5.1）**：只有 2 个冲突。L10n 的改造确实压小了耦合面。
- **2026-10-13（修 1.5.1）**：上游新测试暴露两个真 bug——带编号的工程标签
  一直显示英文（目录里只有 `Untitled`，没有 `Untitled %@`）；拖拽区断言写死
  10pt，中文标签更宽，12 个 tab 把它挤到 6pt。
- **2026-10-24（1.5.7）**：2 个冲突。代码只有 `GIFTimeline.swift` 一处——上游把
  「Original」换成了真实帧延时；appcast 两边各自更新源，取我们的。
  新的镜头特效带来 35 条新文案，顺带把上一轮漏登的 8 个枚举 rawValue 补上，
  目录从 1060 条涨到 1103 条。期间发现「插值的类型决定键」那类静默失配
  （Int 插值查 `%lld`，目录里只有 `%@`），本轮把 fork 自己那两处改掉了。
  另外上游这轮把 RGB Split 的模糊改成向两侧摊开，却没改它的测试——那条断言写死了
  单侧涂抹时的几何，照抄上游必然红。上游的 CI 恰好没跑到它（`verify.yml` 只在改了
  Filters/FilterSheet 之类时才跑 filter 组，而 1.5.7 只动了 `MetalDispersion.swift`）；
  我们这轮改了 FilterSheet，filter 组照跑，所以断言得自己改成新几何。
- **2026-10-25（1.5.8）**：2 个冲突。`CompositorApp.swift` 里两边各加了一个成员——
  我们拆出 `deleteLayerTitle`（每句单独进目录，中文语序才排得开），上游拆出
  `filterMenuItem`（滤镜菜单统一走它）。两个都留，但上游那个的标题要改取
  `localizedName`，不能照抄它的 `rawValue`。appcast 取我们的。
  这轮上游把工程格式版本提到 18（Vignette、Lens Effects、Tonal Contrast 成了调整
  图层），顺带修好了 1.5.4 与 1.5.5 存的工程打不开的问题。**格式版本跟着上游走，
  fork 不单独 +1**——单独加会让工程文件与上游互不兼容。中文的工程格式文档此前只
  写到版本 11（落后 6 个版本），这轮补齐到 18。
  Prism 改了行为：单双向可选、Offset 为 0 也生效、Blur 取代 Reach。带来 8 条新文案、
  5 条废弃文案（旧的 Reach 与两条 Threshold 说明）。

---

## 这个 fork 改过上游什么

除汉化外还有几处，都是 fork 需要的：

| 改动 | 为什么 |
|---|---|
| `CFBundleDisplayName` = 「Compositor 中文版」 | 在「应用程序」里区分于上游英文版 |
| About 面板 + 译者署名 | 上游没有这个面板，SwiftUI 也不会自动补 |
| `README.zh-CN.md` 及配套文档 | 中文版文档 |
| `.github/workflows/release.yml` | 自动构建 ad-hoc DMG（上游那份需要 Developer ID 证书） |
| `.github/workflows/verify.yml` 的 `localization` job | 本地化不报错，得单独守 |
| `.github/workflows/upstream-watch.yml` | 每天检查上游更新 |
| `.gitignore` 补 `*.profraw` | 测试跑出来的覆盖率产物 |

冲突处理时**上游的文件优先保持上游原样**：`README.md` 只改 fork 必须说明的
地方（语言切换、下载来源、Translations 章节），功能列表等一律不动。
