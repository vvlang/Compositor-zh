#!/bin/bash
# 给这个 fork 的 DMG 签 Sparkle 更新包，并生成自己的 appcast.xml。
#
# 与上游 scripts/publish.sh 的区别：那份发到 robbietilton/Compositor 并用他的
# EdDSA 私钥签名（私钥在他钥匙串里）。这份发到本仓库、用我们自己的密钥——
# `SUPublicEDKey` 里的公钥是配着这把私钥生成的，私钥私钥本身只在
# GitHub Secret（CI）或本机钥匙串里，不进仓库。
#
# 用法:
#   scripts/publish-sparkle.sh <tag> <version> [build]
#
# 例:
#   scripts/publish-sparkle.sh v1.5.2 1.5.2 48
#
# 需要:
#   - SPARKLE_PRIVATE_KEY      EdDSA 私钥（CI 里来自 GitHub Secret）
#   - SIGN_UPDATE              sign_update 可执行文件路径（可选，见下）
#   - gh                       已认证，且对 origin 有写权限
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="vvlang/Compositor-zh"
TAG="${1:?用法: publish-sparkle.sh <tag> <version> [build]}"
VERSION="${2:?用法: publish-sparkle.sh <tag> <version> [build]}"
APP=Compositor

[[ -n "${SPARKLE_PRIVATE_KEY:-}" ]] || {
  echo "✗ 没有 SPARKLE_PRIVATE_KEY。见 docs/maintaining-zh.md 的「Sparkle 自动更新」。"
  exit 1
}

DMG="dist/$APP-$VERSION.dmg"
[[ -f "$DMG" ]] || { echo "✗ 找不到 $DMG，先跑 scripts/package-adhoc-dmg.sh。"; exit 1; }

# sign_update 在 Sparkle 的 artifact 里，但路径随 DerivedData 变。让环境变量
# 指过来，免得写死一条只在这台机器上成立的绝对路径。
SIGN_UPDATE="${SIGN_UPDATE:-}"
if [[ -z "$SIGN_UPDATE" ]]; then
  SIGN_UPDATE=$(find "${HOME}/Library/Caches/CompositorAdhoc/DerivedData/SourcePackages/artifacts" \
    -name sign_update -type f -perm +111 2>/dev/null | head -1)
fi
[[ -x "$SIGN_UPDATE" ]] || {
  echo "✗ 找不到可执行的 sign_update。设置 SIGN_UPDATE 环境变量指过去。"
  exit 1
}

settings=$(xcodebuild -project "$APP.xcodeproj" -scheme "$APP" -configuration Release -showBuildSettings 2>/dev/null)
minimum=$(printf '%s\n' "$settings" | awk -F' = ' '/ LSMinimumSystemVersion = /{gsub(/"/,"",$2); print $2; exit}')
build="${3:-$(printf '%s\n' "$settings" | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}')}"

echo "==> Signing $DMG (build $build)"
# Sparkle 2.6+ 废弃了 -s <key>：从钥匙串读，或 --ed-key-file - 从标准输入读。
# CI 的 runner 每次都是干净环境、没有钥匙串，所以走标准输入——私钥由
# GitHub Secret 以管道送进来，不落盘。
#
# sign_update 输出是一整行：sparkle:edSignature="…" length="…"。用 awk 取 $2 会
# 抓到后面的 length（实测只有 17 个字符的垃圾），所以按属性名精确提取。
signature=$(printf '%s' "$SPARKLE_PRIVATE_KEY" \
  | "$SIGN_UPDATE" --ed-key-file - "$DMG" \
  | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')
# EdDSA 签名固定 88 字符（64 字节的 base64）。短于此说明提取失败或私钥不对——
# 与其把坏签名写进 appcast 让 Sparkle 静默拒绝更新，不如当场停下。
[[ ${#signature} -eq 88 ]] || {
  echo "✗ 签名提取失败（得到 ${#signature} 字符，应为 88）。检查 SPARKLE_PRIVATE_KEY。"
  exit 1
}
echo "    $signature"

echo "==> Publishing Release $TAG"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
  && gh release upload "$TAG" "$DMG" --clobber --repo "$REPO" \
  || gh release create "$TAG" "$DMG" --repo "$REPO" \
       --title "$APP $VERSION 中文版" --prerelease \
       --notes "由 GitHub Actions 构建，Sparkle 自动更新见 appcast.xml。"

echo "==> Writing appcast.xml"
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP 中文版</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <link>https://github.com/$REPO/releases/tag/$TAG</link>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$APP-$VERSION.dmg" sparkle:edSignature="$signature" length="$(stat -f%z "$DMG")" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

git add appcast.xml
git commit -q -m "Publish update feed for $APP $VERSION"
git push origin main

echo "==> Done. SUFeedURL 应指向:"
echo "    https://raw.githubusercontent.com/$REPO/main/appcast.xml"
