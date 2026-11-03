#!/bin/bash
# 彻底卸载 MacEverything。
#
# 会清理：
#   1. 正在运行的应用进程
#   2. /Applications、~/Applications、/Users/Shared 等位置的所有 MacEverything.app
#   3. 索引、缓存、偏好、日志、Saved State、HTTPStorages 等用户数据
#   4. 完全磁盘访问等 TCC 授权记录（tccutil reset All）
#   5. LaunchAgent / LaunchDaemon / 特权 Helper 残留
#   6. LaunchServices 注册
#
# 用法：
#   ./scripts/uninstall-maceverything.sh            # 交互确认
#   ./scripts/uninstall-maceverything.sh --yes      # 直接执行
#   ./scripts/uninstall-maceverything.sh --dry-run  # 只列出将要删除的内容
#
# 说明：脚本不需要 root；只有 /Library 下的系统级残留删除失败时，
# 才会提示你用 sudo 手动处理。App 的签名证书与钥匙串不属于卸载范围。

set -uo pipefail

BUNDLE_ID="com.maceverything.app"
APP_NAME="MacEverything"
LEGACY_BUNDLE_IDS=("com.maceverything.app")

ASSUME_YES=0
DRY_RUN=0

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage ;;
        *) echo "未知参数：$arg"; usage ;;
    esac
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "== 演练模式：只显示将要删除的内容 =="
fi

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "即将彻底卸载 MacEverything："
    echo "  • 应用本体（所有已安装版本）"
    echo "  • 索引、缓存、偏好、日志"
    echo "  • 完全磁盘访问等系统授权"
    echo "  • 开机启动 / 后台项残留"
    echo
    printf "确认继续？[y/N] "
    read -r answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "已取消。"; exit 0 ;;
    esac
fi

removed_count=0
failed_count=0

remove_path() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  将删除：$path"
            removed_count=$((removed_count + 1))
            return
        fi
        if rm -rf "$path" 2>/dev/null; then
            echo "  已删除：$path"
            removed_count=$((removed_count + 1))
        else
            echo "  ✗ 删除失败（可能需要 sudo）：$path"
            failed_count=$((failed_count + 1))
        fi
    fi
}

echo
echo "== 1. 退出正在运行的进程 =="
for proc in "$APP_NAME" MacEverythingMCP; do
    if pgrep -x "$proc" >/dev/null 2>&1; then
        echo "  结束进程：$proc"
        if [ "$DRY_RUN" -eq 0 ]; then
            pkill -TERM -x "$proc" 2>/dev/null || true
        fi
    fi
done
if [ "$DRY_RUN" -eq 0 ]; then
    sleep 1
    for proc in "$APP_NAME" MacEverythingMCP; do
        pkill -KILL -x "$proc" 2>/dev/null || true
    done
fi

echo
echo "== 2. 查找并卸载所有已安装的 App =="
declare -a app_paths=()
while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
        /Applications/*/*) ;;                    # 项目构建目录等嵌套路径不处理
        /Applications/*.app) app_paths+=("$path") ;;
        "$HOME"/Applications/*.app) app_paths+=("$path") ;;
        /Users/Shared/*.app) app_paths+=("$path") ;;
    esac
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null)

for path in /Applications/"$APP_NAME".app "$HOME"/Applications/"$APP_NAME".app; do
    [ -d "$path" ] && app_paths+=("$path")
done

# 去重
if [ "${#app_paths[@]}" -gt 0 ]; then
    deduped=()
    while IFS= read -r path; do
        [ -n "$path" ] && deduped+=("$path")
    done < <(printf '%s\n' "${app_paths[@]}" | awk '!seen[$0]++')
    app_paths=("${deduped[@]}")
fi

if [ "${#app_paths[@]}" -eq 0 ]; then
    echo "  未发现已安装的 App"
fi

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
for path in "${app_paths[@]:-}"; do
    [ -n "$path" ] || continue
    if [ "$DRY_RUN" -eq 0 ]; then
        "$LSREGISTER" -u "$path" >/dev/null 2>&1 || true
    fi
    remove_path "$path"
done

echo
echo "== 3. 清理用户数据 =="
user_items=(
    "$HOME/Library/Application Support/$APP_NAME"
    "$HOME/Library/Application Support/$BUNDLE_ID"
    "$HOME/Library/Caches/$BUNDLE_ID"
    "$HOME/Library/Caches/$APP_NAME"
    "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
    "$HOME/Library/HTTPStorages/$BUNDLE_ID"
    "$HOME/Library/WebKit/$BUNDLE_ID"
    "$HOME/Library/Cookies/$BUNDLE_ID.binarycookies"
    "$HOME/Library/Containers/$BUNDLE_ID"
    "$HOME/Library/Application Scripts/$BUNDLE_ID"
    "$HOME/Library/Logs/$APP_NAME"
    "$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
)
for item in "${user_items[@]}"; do
    remove_path "$item"
done

# 通配的残留（崩溃日志、Group Containers、LaunchAgent 变体等）
while IFS= read -r path; do
    remove_path "$path"
done < <(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name "$APP_NAME*" 2>/dev/null)
while IFS= read -r path; do
    remove_path "$path"
done < <(find "$HOME/Library/Group Containers" -maxdepth 1 -iname "*maceverything*" 2>/dev/null)
while IFS= read -r path; do
    remove_path "$path"
done < <(find "$HOME/Library/LaunchAgents" -maxdepth 1 -name "*$BUNDLE_ID*" 2>/dev/null)

if [ "$DRY_RUN" -eq 0 ]; then
    # 让 cfprefsd 立即丢弃旧偏好缓存，避免重装后读回旧值
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

echo
echo "== 4. 清理系统级残留 =="
remove_path "/Library/Application Support/$APP_NAME"
while IFS= read -r path; do
    remove_path "$path"
done < <(find /Library/LaunchAgents /Library/LaunchDaemons -maxdepth 1 -iname "*$BUNDLE_ID*" 2>/dev/null)
while IFS= read -r path; do
    remove_path "$path"
done < <(find /Library/PrivilegedHelperTools -maxdepth 1 -iname "*$BUNDLE_ID*" 2>/dev/null)

if command -v pkgutil >/dev/null 2>&1; then
    while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  将注销安装包记录：$pkg"
        else
            pkgutil --forget "$pkg" >/dev/null 2>&1 \
                && echo "  已注销安装包记录：$pkg" \
                || echo "  ✗ 注销失败（可能需要 sudo）：$pkg"
        fi
    done < <(pkgutil --pkgs 2>/dev/null | grep -i "$BUNDLE_ID" || true)
fi

echo
echo "== 5. 重置系统授权记录（TCC）=="
for id in "${LEGACY_BUNDLE_IDS[@]}"; do
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "  将重置授权：$id"
        continue
    fi
    if tccutil reset All "$id" >/dev/null 2>&1; then
        echo "  已重置全部授权：$id"
    else
        echo "  ✗ 授权重置失败：$id"
        failed_count=$((failed_count + 1))
    fi
done

echo
echo "== 6. 检查登录项 / 后台项 =="
if command -v sfltool >/dev/null 2>&1; then
    btm_output="$(sfltool dumpbtm 2>/dev/null || true)"
    case "$btm_output" in
        *"$BUNDLE_ID"*)
            if [ "$DRY_RUN" -eq 1 ]; then
                echo "  检测到后台项：${BUNDLE_ID}（需在系统设置中手动移除）"
            else
                echo "  检测到后台项：$BUNDLE_ID"
                echo "  删除 App 后该条目仍会留在系统设置里；它不影响重新安装，重装后会被新版本复用。"
                echo "  如需彻底移除，执行下面命令后点选 MacEverything 再按减号："
                echo "    open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension'"
            fi
            ;;
    esac
fi

echo
echo "== 7. 校验 =="
remaining=0
for path in "${app_paths[@]:-}"; do
    [ -n "$path" ] && [ -e "$path" ] && { echo "  仍存在：$path"; remaining=$((remaining + 1)); }
done
for id in "${LEGACY_BUNDLE_IDS[@]}"; do
    leftovers="$(mdfind "kMDItemCFBundleIdentifier == '$id'" 2>/dev/null || true)"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        case "$path" in
            /Applications/*/*) ;;
            /Applications/*.app|"$HOME"/Applications/*.app|/Users/Shared/*.app)
                echo "  Spotlight 仍能搜到：$path"
                remaining=$((remaining + 1))
                ;;
        esac
    done <<< "$leftovers"
done

echo
if [ "$DRY_RUN" -eq 1 ]; then
    echo "演练完成，共将删除 $removed_count 项。"
    exit 0
fi

if [ "$remaining" -eq 0 ]; then
    echo "卸载完成：应用、数据与授权记录均已清理。"
else
    echo "卸载基本完成，但仍有 $remaining 处残留，请按上面的提示处理。"
fi
if [ "$failed_count" -gt 0 ]; then
    echo "有 $failed_count 项因权限不足未能删除；可在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中给终端授权后重试。"
    exit 1
fi
