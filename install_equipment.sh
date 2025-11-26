#!/bin/bash
set -e

echo "🚀 Hexo Butterfly 装备页魔改开始..."

# 0. 检查 butterfly 是否存在
if [ ! -d "themes/butterfly" ]; then
    echo "❌ 未找到 themes/butterfly，请先安装 Butterfly 主题！"
    exit 1
fi

# 1. 创建 equipment.pug
echo "📦 注入 PUG 页面..."
mkdir -p themes/butterfly/layout/includes/page
cat << 'PUG' > themes/butterfly/layout/includes/page/equipment.pug
#equipment
  if site.data.equipment
    each i in site.data.equipment
      .equipment-item
        h2.equipment-item-title= i.class_name
        .equipment-item-description= i.description
        .equipment-item-content
          each item, index in i.equipment_list
            .equipment-item-content-item
              .equipment-item-content-item-cover
                img.equipment-item-content-item-image(src=url_for(item.image) alt=item.name)
              .equipment-item-content-item-info
                .equipment-item-content-item-name= item.name
                .equipment-item-content-item-specification= item.specification
                .equipment-item-content-item-description= item.description
                .equipment-item-content-item-toolbar
                  if item.link.includes('http')
                    a.equipment-item-content-item-link(href=item.link target='_blank') 链接
                  else
                    a.equipment-item-content-item-link(href=item.link target='_blank') 文章
PUG

# 2. 添加 page 路由
echo "📌 修改 page.pug 注册 page 类型..."
if ! grep -q "equipment" themes/butterfly/layout/page.pug; then
    sed -i "/when 'friends'/a\ \ \ \ when 'equipment'\n\ \ \ \ \ \ include includes/page/equipment.pug" themes/butterfly/layout/page.pug
fi

# 3. 创建数据文件
echo "📄 创建 equipment.yml..."
mkdir -p source/_data
cat << 'YML' > source/_data/equipment.yml
- class_name: 生产力设备
  description: 提升效率的硬件
  equipment_list:
    - name: MacBook Pro
      specification: M1 Pro / 32GB / 1TB
      description: 性能猛、屏幕好
      image: https://p.zhheo.com/YnW8cc2150681686120255749.png
      link: https://apple.com
    - name: iPhone 13 Pro
      specification: 256GB
      description: 120Hz 真香
      image: https://p.zhheo.com/TofzQM2219061686120261484.png
      link: https://apple.com
YML

# 4. 创建页面
echo "📘 创建 /equipment 页面..."
mkdir -p source/equipment
cat << 'MD' > source/equipment/index.md
---
title: 我的装备
date: 2025-11-26 12:00:00
type: equipment
aside: false
---
MD

# 5. 注入 CSS
echo "🎨 注入 CSS..."
mkdir -p themes/butterfly/source/css
cat << 'CSS' > themes/butterfly/source/css/equipment.css
#equipment { margin-top: 26px; }
.equipment-item-content { display: flex; flex-wrap: wrap; gap: 12px; }
.equipment-item-content-item { width: calc(25% - 12px); border-radius: 14px; overflow: hidden; background: var(--heo-card-bg); border: var(--style-border-always); box-shadow: var(--heo-shadow-border); position: relative; }
@media(max-width:1200px){ .equipment-item-content-item { width: calc(50% - 12px);} }
@media(max-width:768px){ .equipment-item-content-item { width: 100%; } }
.equipment-item-content-item-cover { height: 200px; background: var(--heo-secondbg); display:flex; justify-content:center; }
.equipment-item-content-item-image { object-fit: cover; height: 100%; width:100%; }
.equipment-item-content-item-info { padding: 16px; }
.equipment-item-content-item-name { font-size:18px;font-weight:bold;margin-bottom:6px; }
.equipment-item-content-item-description { font-size:14px;color:var(--heo-secondtext);height: 60px;overflow:hidden;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical; }
.equipment-item-content-item-toolbar { position:absolute;bottom:12px;width:100%;padding:0 16px;display:flex;justify-content:flex-start; }
.equipment-item-content-item-link { background: var(--heo-gray-op);padding:4px 10px;border-radius:8px;font-size:12px; }
.equipment-item-content-item-link:hover { background:var(--heo-main);color:white; }
CSS

# 注入到主题 config
echo "🧩 写入注入配置..."
if ! grep -q "equipment.css" themes/butterfly/_config.yml; then
cat << 'INJECT' >> themes/butterfly/_config.yml

inject:
  head:
    - <link rel="stylesheet" href="/css/equipment.css">
INJECT
fi

# 6. 构建 Hexo
echo "⚡ 构建 Hexo..."
hexo clean
hexo generate

echo "🎉 装备页魔改成功！访问： /equipment"
