#!/bin/bash
set -e

##############################################
# 0. 基础检查
##############################################

if ! command -v git &>/dev/null; then
    echo "❌ 错误：未安装 git"
    exit 1
fi

# 必须在 git 仓库内运行
if [ ! -d ".git" ]; then
    echo "❌ 当前目录不是 Git 仓库"
    exit 1
fi

# 网络
echo "🌐 正在检查 GitHub 网络连通..."
if ! curl -Is https://github.com --max-time 5 >/dev/null; then
    echo "❌ 无法连接 GitHub，请检查网络"
    exit 1
fi

##############################################
# 1. 输入新仓库地址
##############################################

echo -n "🔗 输入新的 GitHub SSH / HTTPS 地址："
read NEW_ORIGIN

# 支持 SSH 或 HTTPS 两种格式
if [[ ! $NEW_ORIGIN =~ ^git@github\.com:.+/.+\.git$ ]] &&
   [[ ! $NEW_ORIGIN =~ ^https://github\.com/.+/.+\.git$ ]]; then
    echo "❌ 仓库地址格式不正确"
    exit 1
fi

##############################################
# 2. 替换 origin
##############################################

echo "⚙️ 移除旧 origin（如果存在）..."
git remote remove origin 2>/dev/null || true

echo "➕ 添加新 origin: $NEW_ORIGIN"
git remote add origin "$NEW_ORIGIN"

##############################################
# 3. 检查 main 分支是否存在
##############################################

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "ℹ️ 当前分支为：$CURRENT_BRANCH"
    echo "👉 将当前分支重命名为 main"
    git branch -M main
fi

##############################################
# 4. 推送确认
##############################################

echo "⚡ 即将推送当前项目到新仓库：$NEW_ORIGIN"
read -p "确认推送？(Y/n): " pushok
[[ "$pushok" == "n" || "$pushok" == "N" ]] && exit 0

##############################################
# 5. 推送
##############################################

if git push -u origin main; then
    echo "🎉 替换成功！项目已推送到新仓库：$NEW_ORIGIN"
else
    echo "❌ 推送失败！"
    echo "可能原因："
    echo "- 仓库不存在 / 无权限"
    echo "- SSH 未配置"
    echo "- 网络波动"
    exit 1
fi

echo "✅ 完成：origin 已切换 + 推送完成"
