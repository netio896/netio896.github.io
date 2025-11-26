cat <<'EOF' > /root/install_pve9_upgrade_kit.sh
#!/bin/bash
set -e

echo "=== PVE9 Upgrade Kit Installer ==="
echo "Checking system compatibility..."

# 更宽松的系统类型检查
if [ ! -f /etc/pve/version ] && [ ! -d /etc/pve ] && ! command -v pveversion >/dev/null 2>&1; then
    echo "⚠️  这可能不是 Proxmox VE 系统，但继续安装工具包..."
    read -p "继续安装？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "安装取消"
        exit 1
    fi
fi

# --- 用户配置区 ---
BASE="/opt/pve9-upgrade-kit"
BIN="/usr/local/sbin"
CONFIG_DIR="$BASE/config"

mkdir -p "$BASE" "$CONFIG_DIR"
echo "Install path: $BASE"

# -------------------------
# 通用函数：安全写脚本
# -------------------------
write_script() {
  local path="$1"
  local content="$2"
  echo "  → creating $(basename "$path")"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<SCRIPT_CONTENT
$content
SCRIPT_CONTENT
  chmod +x "$path"
}

# =================================================
# 1) 创建配置文件（用户可修改）
# =================================================
CONFIG_FILE='
# PVE备份配置 - 安装后请修改这些参数
BACKUP_DIR="/backup"
NAS_HOST="192.168.88.89"
NAS_DIR_PATH="/vol2/1000/pve-backup"
NAS_USER="root"

# 备份保留策略
KEEP_BACKUPS=3
COMPRESSION="zstd"  # zstd 或 gzip
'

echo "$CONFIG_FILE" > "$CONFIG_DIR/backup.conf"
chmod 644 "$CONFIG_DIR/backup.conf"

# =================================================
# 1) 全套备份脚本（修复版）
# =================================================
FULL_BACKUP_SCRIPT='
#!/bin/bash
set -e
set -o pipefail

# 加载配置
CONFIG_DIR="$(dirname "$0")/config"
if [ -f "$CONFIG_DIR/backup.conf" ]; then
    source "$CONFIG_DIR/backup.conf"
else
    echo "⚠️  配置文件不存在，使用默认值"
    BACKUP_DIR="/backup"
    NAS_HOST="192.168.88.89"
    NAS_DIR_PATH="/vol2/1000/pve-backup"
    NAS_USER="root"
    KEEP_BACKUPS=3
    COMPRESSION="zstd"
fi

echo "=== PVE Full Backup (Safe Edition) ==="
echo "Backup dir: $BACKUP_DIR"
echo "NAS target: ${NAS_USER}@${NAS_HOST}:${NAS_DIR_PATH}"

# 检查是否为 PVE 环境
if ! command -v pvesm >/dev/null 2>&1; then
    echo "❌ 这不是 PVE 系统，无法执行备份"
    exit 1
fi

# 0. 创建目录
echo "[0] 准备目录..."
mkdir -p "$BACKUP_DIR/pve-config" "$BACKUP_DIR/vm" "$BACKUP_DIR/system"

# 测试 NAS 连接
NAS_ONLINE=0
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$NAS_USER@$NAS_HOST" "echo NAS连接测试成功" >/dev/null 2>&1; then
    ssh "$NAS_USER@$NAS_HOST" "mkdir -p ${NAS_DIR_PATH}/pve-config ${NAS_DIR_PATH}/vm ${NAS_DIR_PATH}/system"
    NAS_ONLINE=1
    echo "✅ NAS 连接成功"
else
    echo "⚠️  NAS 连接失败，跳过远程同步"
fi

# 1. 备份 PVE 配置（排除缓存和临时文件）
echo "[1] 备份 PVE 配置..."
CFG_FILE="$BACKUP_DIR/pve-config/pve-config-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz"
if tar czf "$CFG_FILE" \
  --exclude="*/cache/*" \
  --exclude="*/tmp/*" \
  /etc/pve /etc/network /etc/hosts /etc/fstab /etc/systemd \
  /root/.ssh /root/.bashrc /root/.profile 2>/dev/null; then
    echo "✅ 配置备份完成: $(du -h "$CFG_FILE" | cut -f1)"
else
    echo "❌ 配置备份失败"
    exit 1
fi

# 2. 备份 VM/CT - 自动选择存储
echo "[2] 检测可用存储..."
BEST_STORE=$(pvesm status 2>/dev/null | awk '"'"'NR>1 && $3=="active" {print $1,$6}'"'"' | sort -nrk2 | head -n1 | awk '"'"'{print $1}'"'"')

if [ -z "$BEST_STORE" ]; then
    BEST_STORE="local"
    echo "⚠️  使用默认存储: $BEST_STORE"
else
    echo "✅ 使用存储: $BEST_STORE"
fi

echo "[2] 备份所有虚拟机..."
if vzdump --all --compress "$COMPRESSION" --mode snapshot --storage "$BEST_STORE" --maxfiles "$KEEP_BACKUPS" --prune-backups "keep-last=$KEEP_BACKUPS"; then
    echo "✅ 虚拟机备份完成"
else
    echo "❌ 虚拟机备份失败"
    # 不退出，继续其他备份
fi

# 3. 系统盘备份（可选）
echo "[3] 检测系统盘..."
ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
if [[ "$ROOT_DEV" =~ /dev/(sd|nvme|vd) ]]; then
    DISK_PATH=$(echo "$ROOT_DEV" | sed -E '"'"'s/p?[0-9]+$//'"'"')
    IMG_FILE="$BACKUP_DIR/system/system-disk-$(hostname)-$(date +%Y%m%d).img.gz"
    
    echo "💾 系统盘: $DISK_PATH -> $IMG_FILE"
    read -p "⚠️  系统盘备份需要很长时间且占用大量空间，继续？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "开始备份系统盘（低优先级运行）..."
        if ionice -c 3 nice -n 19 dd if="$DISK_PATH" bs=4M status=progress 2>/dev/null | gzip > "$IMG_FILE"; then
            echo "✅ 系统盘备份完成: $(du -h "$IMG_FILE" | cut -f1)"
        else
            echo "❌ 系统盘备份失败"
        fi
    else
        echo "⏭️  跳过系统盘备份"
    fi
else
    echo "⏭️  无法识别系统盘，跳过备份"
fi

# 4. 同步到 NAS
if [ "$NAS_ONLINE" -eq 1 ]; then
    echo "[4] 同步到 NAS..."
    if rsync -avh --progress "$BACKUP_DIR"/ "$NAS_USER@$NAS_HOST:$NAS_DIR_PATH"/; then
        echo "✅ NAS 同步完成"
    else
        echo "❌ NAS 同步失败"
    fi
else
    echo "⏭️  NAS 离线，备份仅保存在本地: $BACKUP_DIR"
fi

echo "🎉 备份完成！"
echo "📁 本地备份位置: $BACKUP_DIR"
'

# =================================================
# 2) 升级后健康检查脚本（优化版）
# =================================================
POST_CHECK_SCRIPT='
#!/bin/bash
echo "=== PVE Post-Upgrade Health Check ==="

echo "--- [1] 版本信息 ---"
if command -v pveversion >/dev/null 2>&1; then
    pveversion -v 2>/dev/null | grep -E "(pve-manager|proxmox-ve|pve-kernel)" || echo "❌ 无法获取版本信息"
else
    echo "⏭️  pveversion 命令不可用"
fi

echo -e "\n--- [2] 集群状态 ---"
if [ -f /etc/pve/corosync.conf ]; then
    if command -v pvecm >/dev/null 2>&1; then
        pvecm status 2>/dev/null || echo "⚠️  集群状态检查失败"
    else
        echo "⏭️  pvecm 命令不可用"
    fi
else
    echo "✅ 单节点模式"
fi

echo -e "\n--- [3] 存储状态 ---"
if command -v pvesm >/dev/null 2>&1; then
    pvesm status 2>/dev/null || echo "❌ 存储状态检查失败"
else
    echo "❌ pvesm 命令不可用"
fi

echo -e "\n--- [4] ZFS 状态 ---"
if command -v zpool >/dev/null 2>&1; then
    zpool list 2>/dev/null && echo "✅ ZFS 正常" || echo "⚠️  ZFS 异常"
else
    echo "⏭️  ZFS 未安装"
fi

echo -e "\n--- [5] 运行中的虚拟机 ---"
if command -v qm >/dev/null 2>&1; then
    echo "VM:" && qm list 2>/dev/null | grep running | awk '"'"'{print "  ✅ " $2 " (ID:" $1 ")"}'"'"' || echo "  🔴 无运行中的VM"
else
    echo "⏭️  qm 命令不可用"
fi

if command -v pct >/dev/null 2>&1; then
    echo "CT:" && pct list 2>/dev/null | grep running | awk '"'"'{print "  ✅ " $3 " (ID:" $1 ")"}'"'"' || echo "  🔴 无运行中的CT"
else
    echo "⏭️  pct 命令不可用"
fi

echo -e "\n--- [6] 关键服务状态 ---"
for service in pveproxy pvedaemon pvestatd; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        echo "  ✅ $service: 运行中"
    else
        echo "  ❌ $service: 未运行"
    fi
done

echo -e "\n--- [7] 网络状态 ---"
ip -br addr show | grep -v "lo" | while read -r line; do
    echo "  📶 $line"
done

echo -e "\n=== 检查完成 ==="
'

# =================================================
# 3) 升级准备检查脚本（PVE9 ready check）
# =================================================
READY_CHECK_SCRIPT='
#!/bin/bash
echo "=== PVE 9 升级就绪检查 ==="

# 1. 系统信息
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "📦 系统: $PRETTY_NAME"
fi

# 2. PVE 版本
if command -v pveversion >/dev/null 2>&1; then
    PVE_VERSION=$(pveversion 2>/dev/null | cut -d/ -f2 | cut -d- -f1) || PVE_VERSION="unknown"
    echo "🔖 PVE 版本: $PVE_VERSION"
else
    echo "❌ 这不是 PVE 系统"
    exit 1
fi

# 3. 内核版本
KERNEL=$(uname -r)
echo "💻 内核: $KERNEL"
if [[ "$KERNEL" == 6.* ]]; then
    echo "  ✅ 内核 6.x (符合要求)"
else
    echo "  ⚠️  建议先升级到最新 PVE 8.x 内核"
fi

# 4. 磁盘空间检查
echo "💾 磁盘空间:"
ROOT_FREE_GB=$(df -BG / | awk '"'"'NR==2 {print $4}'"'"' | sed 's/G//')
if [ "$ROOT_FREE_GB" -lt 10 ]; then
    echo "  ❌ 根分区仅剩 ${ROOT_FREE_GB}GB，需要至少 10GB"
else
    echo "  ✅ 根分区剩余 ${ROOT_FREE_GB}GB"
fi

# 5. Ceph 检查
if systemctl is-active --quiet ceph-mon.target 2>/dev/null; then
    echo "⚠️  Ceph 已安装 - 请先参考官方升级指南"
else
    echo "✅ 未检测到 Ceph"
fi

# 6. 订阅状态
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    if grep -q "pve-enterprise" /etc/apt/sources.list.d/pve-enterprise.list; then
        echo "💰 企业订阅: 已配置"
    fi
else
    echo "🔓 无订阅版本: 已配置"
fi

echo -e "\n=== 检查完成 ==="
if command -v pveversion >/dev/null 2>&1; then
    echo "当前 PVE 版本详细信息:"
    pveversion
fi
'

# =================================================
# 4) 硬件 & 网卡报告脚本
# =================================================
HW_REPORT_SCRIPT='
#!/bin/bash
REPORT_FILE="/opt/pve9-upgrade-kit/hw-report-$(date +%Y%m%d-%H%M%S).log"
{
echo "=== PVE 硬件网络报告 ==="
echo "生成时间: $(date)"
echo "主机名: $(hostname)"
echo

echo "--- CPU 信息 ---"
lscpu | grep -E "(Model name|CPU\(s\)|Thread|Core)" | head -5

echo -e "\n--- 内存信息 ---"
free -h

echo -e "\n--- 磁盘布局 ---"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT

echo -e "\n--- 网络接口 ---"
ip -br addr show

echo -e "\n--- 网络配置 ---"
if [ -f /etc/network/interfaces ]; then
    cat /etc/network/interfaces
else
    echo "⚠️  /etc/network/interfaces 不存在"
fi

if command -v pvesm >/dev/null 2>&1; then
    echo -e "\n--- PVE 存储 ---"
    pvesm status 2>/dev/null || echo "pvesm 不可用"
fi

} | tee "$REPORT_FILE"

echo -e "\n✅ 报告已保存: $REPORT_FILE"
'

# =================================================
# 5) PVE9 发布监控脚本
# =================================================
PVE9_MONITOR_SCRIPT='
#!/bin/bash
echo "=== PVE 9 可用性监控 ==="

if ! apt update >/dev/null 2>&1; then
    echo "❌ apt update 失败"
    exit 1
fi

PVE_PKG=$(apt-cache policy proxmox-ve 2>/dev/null | grep -A1 "Candidate:" | tail -1 | awk '"'"'{print $1}'"'"')

if [ -z "$PVE_PKG" ]; then
    echo "❌ 无法获取 proxmox-ve 包信息"
    exit 1
fi

if command -v pveversion >/dev/null 2>&1; then
    CURRENT_VERSION=$(pveversion 2>/dev/null | cut -d/ -f2 | cut -d- -f1 | cut -d. -f1) || CURRENT_VERSION="unknown"
else
    CURRENT_VERSION="unknown"
fi

CANDIDATE_VERSION=$(echo "$PVE_PKG" | cut -d. -f1)

echo "当前安装版本: PVE $CURRENT_VERSION"
echo "仓库候选版本: PVE $CANDIDATE_VERSION"

if [ "$CANDIDATE_VERSION" -ge 9 ] 2>/dev/null; then
    echo -e "\n🎉 PVE 9 已可用！可以开始升级流程"
    echo "运行 'pve-upgrade-assistant' 查看升级步骤"
else
    echo -e "\n⏳ PVE 9 尚未发布，当前最新: $PVE_PKG"
fi
'

# =================================================
# 6) 从 NAS 恢复同步脚本
# =================================================
RESTORE_SYNC_SCRIPT='
#!/bin/bash
set -e

# 加载配置
CONFIG_DIR="$(dirname "$0")/config"
if [ -f "$CONFIG_DIR/backup.conf" ]; then
    source "$CONFIG_DIR/backup.conf"
else
    echo "⚠️  使用默认配置"
    BACKUP_DIR="/backup"
    NAS_HOST="192.168.88.89"
    NAS_DIR_PATH="/vol2/1000/pve-backup"
    NAS_USER="root"
fi

echo "=== 从 NAS 恢复备份 ==="
echo "NAS: $NAS_USER@$NAS_HOST:$NAS_DIR_PATH"
echo "本地: $BACKUP_DIR"

# 检查 NAS 连接
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 "$NAS_USER@$NAS_HOST" "echo NAS连接成功" >/dev/null 2>&1; then
    echo "❌ NAS 连接失败，请检查:"
    echo "  1. 网络连通性"
    echo "  2. SSH 密钥配置"
    echo "  3. NAS 地址和用户权限"
    exit 1
fi

# 检查远程备份是否存在
if ! ssh "$NAS_USER@$NAS_HOST" "[ -d \"$NAS_DIR_PATH\" ] && echo \"备份目录存在\"" >/dev/null 2>&1; then
    echo "❌ 远程备份目录不存在: $NAS_DIR_PATH"
    exit 1
fi

echo "✅ NAS 连接正常，开始同步..."
mkdir -p "$BACKUP_DIR"

if rsync -avh --progress "$NAS_USER@$NAS_HOST:$NAS_DIR_PATH/" "$BACKUP_DIR"/; then
    echo -e "\n✅ 同步完成"
    echo -e "\n📋 恢复指南:"
    echo "1. 查看配置文件: ls $BACKUP_DIR/pve-config/"
    echo "2. 查看虚拟机备份: ls $BACKUP_DIR/vm/"
    echo "3. 恢复 VM: qmrestore <备份文件> <虚拟机ID>"
    echo "4. 恢复 CT: pct restore <容器ID> <备份文件>"
else
    echo "❌ 同步失败"
    exit 1
fi
'

# =================================================
# 7) PVE9 实际升级执行脚本
# =================================================
PVE9_UPGRADE_SCRIPT='
#!/bin/bash
set -e

echo "=== PVE 8 → 9 实际升级执行脚本 ==="
echo "⚠️  警告：此操作不可逆，请确保已完成备份！"
echo

# 检查是否为 PVE 系统
if ! command -v pveversion >/dev/null 2>&1; then
    echo "❌ 这不是 PVE 系统，无法执行升级"
    exit 1
fi

# 最终确认
read -p "❓ 确认已执行完整备份并准备好升级？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ 升级取消"
    exit 1
fi

echo "🚀 开始 PVE 9 升级流程..."

# 步骤1：更新当前系统到最新 PVE 8
echo -e "\n[1/6] 更新到最新 PVE 8..."
apt update
apt dist-upgrade -y

# 步骤2：检查是否需要重启
echo -e "\n[2/6] 检查内核更新..."
if command -v needrestart >/dev/null 2>&1; then
    if [ "$(needrestart -b | grep -c "NEEDRESTART-KEXP:.*Kernel")" -gt 0 ]; then
        echo "⚠️  检测到内核更新，需要重启..."
        read -p "❓ 现在重启？(yes/no): " reboot_now
        if [ "$reboot_now" = "yes" ]; then
            echo "🔄 重启系统..."
            reboot
        else
            echo "⏭️  请稍后手动重启并重新运行此脚本"
            exit 0
        fi
    fi
fi

# 步骤3：修改软件源到 trixie (Debian 13)
echo -e "\n[3/6] 修改软件源到 trixie..."
# 备份原有源
cp /etc/apt/sources.list /etc/apt/sources.list.bak
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    cp /etc/apt/sources.list.d/pve-enterprise.list /etc/apt/sources.list.d/pve-enterprise.list.bak
fi

# 替换为 trixie
sed -i 's/bookworm/trixie/g' /etc/apt/sources.list
if [ -f /etc/apt/sources.list.d/pve-enterprise.list ]; then
    sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-enterprise.list
fi

# 步骤4：更新到 PVE 9
echo -e "\n[4/6] 执行 PVE 9 升级..."
apt update
apt dist-upgrade -y

# 步骤5：清理旧包
echo -e "\n[5/6] 清理旧包..."
apt autoremove --purge -y

# 步骤6：最终重启
echo -e "\n[6/6] 升级完成！需要重启生效..."
echo "📋 重启后请运行: pve-post-upgrade-check"
read -p "❓ 现在重启系统？(yes/no): " final_reboot
if [ "$final_reboot" = "yes" ]; then
    echo "🔄 重启系统..."
    reboot
else
    echo "⚠️  请记住稍后手动重启完成升级"
fi

echo "🎉 PVE 9 升级流程执行完成！"
'

# =================================================
# 8) 升级助手脚本
# =================================================
UPGRADE_ASSISTANT_SCRIPT='
#!/bin/bash
echo "=== PVE 8 → 9 升级助手 ==="
echo

echo "📋 推荐升级流程:"
echo "1.  pve-hw-report             - 保存硬件信息"
echo "2.  pve9-ready-check          - 检查系统状态"  
echo "3.  pve-full-backup           - 完整备份"
echo "4.  pve9-upgrade              - 执行实际升级"
echo "5.  重启系统"
echo "6.  pve-post-upgrade-check    - 升级后验证"
echo

echo "🔧 手动升级步骤（供参考）:"
echo "1. 更新当前系统:"
echo "   apt update && apt dist-upgrade -y"
echo
echo "2. 修改软件源:"
echo "   sed -i 's/bookworm/trixie/g' /etc/apt/sources.list"
echo "   sed -i 's/bookworm/trixie/g' /etc/apt/sources.list.d/pve-enterprise.list"
echo
echo "3. 执行升级:"
echo "   apt update && apt dist-upgrade -y"
echo
echo "4. 重启:"
echo "   reboot"
echo
echo "⚠️  重要提醒:"
echo "   - 确保有完整可用的备份"
echo "   - 在业务低峰期操作"
echo "   - 预留足够时间（1-2小时）"
echo "   - 如有问题可尝试: pve-restore-sync-from-nas"
'

# =================================================
# 安装所有脚本
# =================================================
echo "安装脚本到 $BASE ..."

write_script "$BASE/pve-full-backup.sh" "$FULL_BACKUP_SCRIPT"
write_script "$BASE/pve-post-upgrade-check.sh" "$POST_CHECK_SCRIPT"
write_script "$BASE/pve9-ready-check.sh" "$READY_CHECK_SCRIPT"
write_script "$BASE/pve-hw-report.sh" "$HW_REPORT_SCRIPT"
write_script "$BASE/pve9-monitor.sh" "$PVE9_MONITOR_SCRIPT"
write_script "$BASE/pve-restore-sync-from-nas.sh" "$RESTORE_SYNC_SCRIPT"
write_script "$BASE/pve9-upgrade.sh" "$PVE9_UPGRADE_SCRIPT"
write_script "$BASE/pve-upgrade-assistant.sh" "$UPGRADE_ASSISTANT_SCRIPT"

# 创建软链接
mkdir -p "$BIN"
for script in pve-full-backup pve-post-upgrade-check pve9-ready-check pve-hw-report pve9-monitor pve-restore-sync-from-nas pve9-upgrade pve-upgrade-assistant; do
    if ln -sf "$BASE/$script.sh" "$BIN/$script" 2>/dev/null; then
        echo "  → link: $BIN/$script"
    else
        echo "  ❌ 创建链接失败: $script"
    fi
done

# 创建使用说明
cat > "$BASE/README.md" <<'README'
# PVE9 升级工具包

## 核心升级命令
- `pve9-upgrade` - ★实际执行 PVE8→9 升级
- `pve9-ready-check` - 升级前环境检查  
- `pve-full-backup` - 全量备份(配置+虚拟机+系统)
- `pve-post-upgrade-check` - 升级后健康检查

## 辅助命令
- `pve-hw-report` - 硬件网络信息存档
- `pve-restore-sync-from-nas` - 从NAS恢复备份
- `pve9-monitor` - 检查PVE9可用性
- `pve-upgrade-assistant` - 升级步骤指导

## 配置修改
编辑 `/opt/pve9-upgrade-kit/config/backup.conf` 修改备份设置

## 完整升级流程
1. pve-hw-report (存档硬件信息)
2. pve9-ready-check (环境检查)
3. pve-full-backup (完整备份) 
4. pve9-upgrade (执行升级)
5. reboot (重启)
6. pve-post-upgrade-check (验证)

## 重要提醒
1. 升级前务必完整备份并验证可恢复
2. 在维护窗口操作，预留足够时间
3. 如有问题使用恢复功能
README

echo
echo "🎉 PVE9 升级工具包安装完成！"
echo "========================================"
echo "🚀 核心升级命令:"
echo "  pve9-ready-check          - 升级前检查"
echo "  pve-full-backup           - ★完整备份"  
echo "  pve9-upgrade              - ★执行PVE9升级"
echo "  pve-post-upgrade-check    - 升级后验证"
echo
echo "📋 辅助命令:"
echo "  pve-hw-report             - 硬件信息存档"
echo "  pve-restore-sync-from-nas - 从NAS恢复"
echo "  pve9-monitor              - PVE9可用性"
echo "  pve-upgrade-assistant     - 升级指南"
echo
echo "⚠️  下一步:"
echo "  1. 编辑配置: nano /opt/pve9-upgrade-kit/config/backup.conf"
echo "  2. 测试备份: pve-full-backup"
echo "  3. 执行升级: pve9-upgrade"
echo "========================================"
EOF

# 设置执行权限
chmod +x /root/install_pve9_upgrade_kit.sh

echo "✅ 修复版安装脚本创建完成！"
echo "现在运行: ./install_pve9_upgrade_kit.sh"
