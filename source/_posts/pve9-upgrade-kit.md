---
title: "PVE9 升级工具包（备份 + 升级 + 恢复一条龙）"
date: 2025-11-26
categories:
  - Proxmox
  - PVE9
tags:
  - PVE
  - 升级
  - 备份
  - 自动化
---

这篇是给我自己和未来的我用的「**PVE9 升级工具包**」备忘录：

- 一键安装工具包  
- 升级前检查（ready-check）  
- 全量备份（配置 + VM/CT + 系统盘）  
- 同步到 NAS / 从 NAS 恢复  
- 真正执行 PVE 8 → 9 升级  
- 升级后健康检查  

整套思路：  
**先硬件报告 → 环境检查 → 备份 → 升级 → 验证 → 出事就从 NAS 拉回。**

---

## 🔥 一图流（命令流程）

```bash
# 1）安装升级工具包
curl -o /root/install_pve9_upgrade_kit.sh https://你的域名/files/pve9-upgrade-kit.sh
chmod +x /root/install_pve9_upgrade_kit.sh
/root/install_pve9_upgrade_kit.sh

# 2）升级前硬件&环境
pve-hw-report
pve9-ready-check

# 3）完整备份 + 同步 NAS
pve-full-backup

# 4）真正执行 PVE9 升级
pve9-upgrade

# 5）重启后做健康检查
pve-post-upgrade-check
```

> 提醒自己：升级前一定要确认 VM 备份可恢复 + NAS 同步 OK。

---

## ⬇️ 下载脚本（给未来的我 / 别的机器用）

下面这个按钮就是脚本本体，已经放在 `source/files/pve9-upgrade-kit.sh`：

```html
<p style="margin: 1.5em 0;">
  <a href="/files/pve9-upgrade-kit.sh" download
     style="display:inline-block;padding:0.6em 1.4em;border-radius:0.4em;
            border:1px solid #888;text-decoration:none;font-weight:600;">
    💾 下载脚本：pve9-upgrade-kit.sh
  </a>
</p>
```

---

## 🧪 升级前 Checklist（防翻车清单）

- [ ] 当前 PVE 是 **8.x 最新版本**（先跑一次 `apt update && apt dist-upgrade -y`）  
- [ ] `pve-hw-report` 已经导出硬件&网络报告，并保存到 NAS / 本地电脑  
- [ ] `pve9-ready-check` 没有红色致命问题（磁盘空间、内核、Ceph 等）  
- [ ] `pve-full-backup` 已成功跑完，虚拟机备份在本机 & NAS 都存在  
- [ ] 业务低峰、有人值守、可以接受 1–2 小时维护窗口  
- [ ] 能远程 IPMI / KVM / iDRAC 之类的「救命入口」

---

## 🧷 核心命令速查表

| 命令                     | 作用说明                             |
|--------------------------|--------------------------------------|
| `pve-hw-report`          | 导出 CPU/内存/磁盘/网卡/存储完整报告 |
| `pve9-ready-check`       | 检查是否适合升 PVE9                  |
| `pve-full-backup`        | 配置 + VM/CT + （可选）系统盘全备份  |
| `pve9-upgrade`           | 真正执行 PVE 8 → 9 升级              |
| `pve-post-upgrade-check` | 升级后健康检查                        |
| `pve9-monitor`           | 看 PVE9 是否已在仓库中可用           |
| `pve-restore-sync-from-nas` | 从 NAS 拉回整套备份             |
| `pve-upgrade-assistant`  | 文字版升级指南                        |

---

## 🧨 完整安装脚本（折叠查看）

> 这块就是你那整份超长脚本。  
> 我用 `<details>` 折叠 + `{% raw %}` 包起来，避免 Hexo 把里面的 `{{ }}` / `{% %}` 搞乱。

{% raw %}
<details>
  <summary style="cursor:pointer;font-weight:600;margin:1em 0;">
    👇 展开查看完整安装脚本（install_pve9_upgrade_kit.sh）
  </summary>

```bash
# 这里开始粘贴你完整的脚本内容
# 从：cat <<'EOF' > /root/install_pve9_upgrade_kit.sh
# 一直到：echo "现在运行: ./install_pve9_upgrade_kit.sh"

cat <<'EOF' > /root/install_pve9_upgrade_kit.sh
#!/bin/bash
set -e

echo "=== PVE9 Upgrade Kit Installer ==="
echo "Checking system compatibility..."

# ...（把你整份脚本完整贴进来，不要删）...

echo "✅ 修复版安装脚本创建完成！"
echo "现在运行: ./install_pve9_upgrade_kit.sh"
EOF

chmod +x /root/install_pve9_upgrade_kit.sh
echo "✅ 脚本已创建：/root/install_pve9_upgrade_kit.sh"
```

</details>
{% endraw %}

---

## 🧠 自己给自己的几条备注

- 这个工具包默认备份到：`/backup`，NAS：`192.168.88.89:/vol2/1000/pve-backup`  
  升级前记得改 `/opt/pve9-upgrade-kit/config/backup.conf`
- 如果以后 PVE 官方升级流程变动，可以只改 `pve9-upgrade.sh` 那一个文件  
- 真出事了：  
  - 先看 `pve-hw-report` 保存的硬件信息  
  - 再用 `pve-restore-sync-from-nas` 拉回备份  
  - 再用 `qmrestore` / `pct restore` 一台台拉 VM/CT

> 这篇主要是给未来的自己一个“安全感脚本”，PVE9 升级只做一次，但备份工具可以一直用下去。
