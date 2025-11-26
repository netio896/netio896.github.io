#!/data/data/com.termux/files/usr/bin/bash

echo "🔥 Yo! 新文章来啦～"
read -p "请输入文章标题: " TITLE

if [ -z "$TITLE" ]; then
  echo "❌ 标题不能为空"
  exit 1
fi

# 生成 slug
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g')

# 文章路径
POST_FILE="source/_posts/${SLUG}.md"

# 获取日期
DATE=$(date +"%Y-%m-%d %H:%M:%S")

# 创建 Markdown 模板
cat <<EOT > "$POST_FILE"
---
title: "$TITLE"
date: $DATE
categories: [随手记]
tags: []
---

## 😎 写点东西吧～

这里是正文内容～
EOT

echo "✨ 已创建: $POST_FILE"

echo "⚡ 自动生成静态文件..."
npx hexo generate

echo "🎉 完成！快去写你的内容吧！"
