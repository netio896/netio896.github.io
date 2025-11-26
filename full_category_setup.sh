#!/bin/bash

set -e
echo "🔥 启动 Hexo 滿血分类体系构建器..."

CATS=("docker" "ai" "pve" "nas" "pi5")

# ===========================
# 1) Scaffold 模板增强
# ===========================
echo "📦 更新 scaffold/post.md ..."
cat << 'SCF' > scaffolds/post.md
---
title: {{ title }}
date: {{ date }}
categories:
  - 未分类
tags:
---
SCF

# ===========================
# 2) 自动创建分类页面
# ===========================
echo "📘 自动创建分类页面..."

mkdir -p source/categories

cat << 'MD' > source/categories/index.md
---
title: 分类
type: "categories"
---
MD

# ===========================
# 3) 为每个分类创建专属 index 页面
# ===========================
echo "📁 为每个分类生成独立页面..."

for C in "${CATS[@]}"; do
    mkdir -p "source/categories/${C}"
    cat << EOM > "source/categories/${C}/index.md"
---
title: ${C^^}
type: "category"
category: ${C}
---
EOM
done

# ===========================
# 4) 自动生成分类导航页（卡片样式）
# ===========================
echo "🎨 构建分类导航页（卡片 UI）..."

mkdir -p source/categories/_nav

cat << 'NAV' > source/categories/_nav/index.md
---
title: 技术分类导航
type: "page"
sidebar: false
---

<div class="cat-nav-grid">
  <a class="cat-card" href="/categories/docker/"><span>🐳 Docker</span></a>
  <a class="cat-card" href="/categories/ai/"><span>🤖 AI</span></a>
  <a class="cat-card" href="/categories/pve/"><span>🖥 PVE</span></a>
  <a class="cat-card" href="/categories/nas/"><span>💾 NAS</span></a>
  <a class="cat-card" href="/categories/pi5/"><span>🍓 Pi5</span></a>
</div>
NAV

# ===========================
# 5) 注入分类导航样式
# ===========================
echo "🎨 注入 CSS 样式 ..."

mkdir -p themes/butterfly/source/css

cat << 'CSS' > themes/butterfly/source/css/catnav.css
.cat-nav-grid {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  margin-top: 20px;
}

.cat-card {
  padding: 20px;
  background: var(--heo-card-bg);
  border-radius: 12px;
  border: var(--style-border-always);
  box-shadow: var(--heo-shadow-border);
  flex: 1 1 calc(33% - 16px);
  text-align: center;
  font-size: 20px;
  transition: .25s;
}

.cat-card:hover {
  transform: translateY(-6px);
  background: var(--heo-main);
  color: #fff;
}
@media(max-width:900px){
  .cat-card { flex: 1 1 100%; }
}
CSS

# 注入到 Butterfly 配置
if ! grep -q "catnav.css" themes/butterfly/_config.yml; then
cat << 'INJ' >> themes/butterfly/_config.yml

inject:
  head:
    - <link rel="stylesheet" href="/css/catnav.css">
INJ
fi

# ===========================
# 6) 构建站点
# ===========================
echo "⚡ 构建 Hexo 静态文件 ..."
hexo clean && hexo generate

echo "🎉 全部完成！"
echo "👉 分类总览:           /categories/"
echo "👉 分类导航卡片页面:   /categories/_nav/"
echo "👉 独立分类页面:       /categories/[分类名称]/"
