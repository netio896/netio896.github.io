#!/bin/bash

# Git 远程仓库管理脚本 - Termux 增强版
# 支持 SSH Key 生成、用户配置和远程仓库管理

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 默认配置变量
SSH_DIR="/data/data/com.termux/files/home/.ssh"
TEMP_DIR="/data/data/com.termux/files/usr/tmp"
KEY_NAME="id_ed25519_termux"
DEFAULT_GIT_USER_NAME="xiaoyan-io"
DEFAULT_GIT_USER_EMAIL="network.io.biz@gmail.com"

# 当前配置
CURRENT_GIT_USER_NAME=$(git config --global user.name || echo "")
CURRENT_GIT_USER_EMAIL=$(git config --global user.email || echo "")

# 输出函数
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_debug() { echo -e "${CYAN}🐛 $1${NC}"; }

# 检查依赖
check_dependencies() {
    log_info "检查系统依赖..."
    local deps=("git" "ssh" "ssh-keygen")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "缺少依赖: $dep"
            log_info "正在安装必要包..."
            pkg install git openssh -y
            break
        fi
    done
}

# 显示当前 Git 配置
show_git_config() {
    log_info "当前 Git 全局配置:"
    echo "👤 用户名: ${CURRENT_GIT_USER_NAME:-未设置}"
    echo "📧 邮箱: ${CURRENT_GIT_USER_EMAIL:-未设置}"
    echo ""
}

# 替换 Git 用户信息
replace_git_user() {
    log_info "🔧 替换 Git 用户信息..."
    
    # 显示当前配置
    show_git_config
    
    # 获取新的用户信息
    local new_name new_email
    
    read -rp "请输入新的 Git 用户名 [当前: ${CURRENT_GIT_USER_NAME:-空}]: " new_name
    read -rp "请输入新的 Git 邮箱 [当前: ${CURRENT_GIT_USER_EMAIL:-空}]: " new_email
    
    # 如果用户直接回车，则使用当前值
    if [[ -z "$new_name" && -n "$CURRENT_GIT_USER_NAME" ]]; then
        new_name="$CURRENT_GIT_USER_NAME"
    fi
    
    if [[ -z "$new_email" && -n "$CURRENT_GIT_USER_EMAIL" ]]; then
        new_email="$CURRENT_GIT_USER_EMAIL"
    fi
    
    # 验证输入
    if [[ -z "$new_name" ]]; then
        log_error "用户名不能为空"
        return 1
    fi
    
    if [[ -z "$new_email" ]]; then
        log_error "邮箱不能为空"
        return 1
    fi
    
    # 应用新配置
    git config --global user.name "$new_name"
    git config --global user.email "$new_email"
    
    # 更新当前配置变量
    CURRENT_GIT_USER_NAME="$new_name"
    CURRENT_GIT_USER_EMAIL="$new_email"
    
    log_success "Git 用户信息已更新"
    show_git_config
    
    # 询问是否更新现有仓库的用户信息
    log_warning "是否更新现有仓库的提交者信息？(y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        update_existing_repos_author
    fi
}

# 更新现有仓库的提交者信息
update_existing_repos_author() {
    log_info "查找并更新现有仓库的提交者信息..."
    
    read -rp "请输入要搜索的目录路径 [回车使用当前目录]: " search_dir
    search_dir="${search_dir:-$PWD}"
    
    if [[ ! -d "$search_dir" ]]; then
        log_error "目录不存在: $search_dir"
        return 1
    fi
    
    local repo_count=0
    
    find "$search_dir" -type d -name ".git" 2>/dev/null | while read -r git_dir; do
        local repo_dir=$(dirname "$git_dir")
        ((repo_count++))
        
        log_info "处理仓库 $repo_count: $repo_dir"
        
        # 进入仓库目录并更新本地配置
        (
            cd "$repo_dir"
            
            # 保存原始远程 URL（用于显示）
            local remote_url=$(git remote get-url origin 2>/dev/null || echo "无远程")
            
            # 更新仓库特定的用户配置
            git config user.name "$CURRENT_GIT_USER_NAME"
            git config user.email "$CURRENT_GIT_USER_EMAIL"
            
            log_success "更新仓库: $(basename "$repo_dir")"
            log_debug "远程: $remote_url"
            log_debug "新用户: $CURRENT_GIT_USER_NAME <$CURRENT_GIT_USER_EMAIL>"
        )
    done
    
    if [[ $repo_count -eq 0 ]]; then
        log_warning "在 $search_dir 中未找到 Git 仓库"
    else
        log_success "共更新了 $repo_count 个仓库的用户配置"
    fi
}

# 重置 Git 用户信息为默认值
reset_git_user_to_default() {
    log_info "重置 Git 用户信息为默认值..."
    
    git config --global user.name "$DEFAULT_GIT_USER_NAME"
    git config --global user.email "$DEFAULT_GIT_USER_EMAIL"
    
    # 更新当前配置变量
    CURRENT_GIT_USER_NAME="$DEFAULT_GIT_USER_NAME"
    CURRENT_GIT_USER_EMAIL="$DEFAULT_GIT_USER_EMAIL"
    
    log_success "已重置为默认用户信息"
    show_git_config
}

# 生成 SSH Key
generate_ssh_key() {
    log_info "生成新的 SSH Key..."
    
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    
    # 检查是否已存在密钥
    if [[ -f "$SSH_DIR/$KEY_NAME" ]]; then
        log_warning "SSH Key 已存在，是否重新生成？(y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "使用现有 SSH Key"
            return
        fi
        # 备份旧密钥
        local backup_dir="$SSH_DIR/backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        mv "$SSH_DIR/$KEY_NAME"* "$backup_dir/" 2>/dev/null || true
        log_success "旧密钥已备份到: $backup_dir"
    fi
    
    # 生成 Ed25519 密钥
    log_info "生成 Ed25519 密钥..."
    ssh-keygen -t ed25519 -C "$CURRENT_GIT_USER_EMAIL" -f "$SSH_DIR/$KEY_NAME" -N ""
    chmod 600 "$SSH_DIR/$KEY_NAME"
    chmod 644 "$SSH_DIR/$KEY_NAME.pub"
    
    log_success "SSH Key 生成完成"
    
    # 显示公钥
    echo ""
    log_info "🔑 公钥内容 (复制到 GitHub/GitLab):"
    echo "=========================================="
    cat "$SSH_DIR/$KEY_NAME.pub"
    echo "=========================================="
    echo ""
}

# 配置 SSH
configure_ssh() {
    log_info "配置 SSH..."
    
    local ssh_config="$SSH_DIR/config"
    
    # 创建或更新 SSH 配置
    cat > "$ssh_config" << EOF
# GitHub
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_DIR/$KEY_NAME
    IdentitiesOnly yes
    
# GitLab
Host gitlab.com
    HostName gitlab.com
    User git
    IdentityFile $SSH_DIR/$KEY_NAME
    IdentitiesOnly yes

# Gitee
Host gitee.com
    HostName gitee.com
    User git
    IdentityFile $SSH_DIR/$KEY_NAME
    IdentitiesOnly yes
EOF
    
    chmod 600 "$ssh_config"
    log_success "SSH 配置完成"
}

# 测试 SSH 连接
test_ssh_connection() {
    log_info "测试 SSH 连接..."
    
    local hosts=("github.com" "gitlab.com" "gitee.com")
    
    for host in "${hosts[@]}"; do
        log_info "测试连接到 $host..."
        if ssh -T -o ConnectTimeout=10 -o StrictHostKeyChecking=no "git@$host" 2>&1 | grep -q "successfully authenticated"; then
            log_success "$host - SSH 连接成功"
        else
            log_warning "$host - SSH 认证待配置，请将公钥添加到平台"
        fi
    done
}

# 配置 Git 用户信息
setup_git_config() {
    log_info "配置 Git 用户信息..."
    
    # 如果当前没有配置，使用默认值
    if [[ -z "$CURRENT_GIT_USER_NAME" ]]; then
        git config --global user.name "$DEFAULT_GIT_USER_NAME"
        CURRENT_GIT_USER_NAME="$DEFAULT_GIT_USER_NAME"
    fi
    
    if [[ -z "$CURRENT_GIT_USER_EMAIL" ]]; then
        git config --global user.email "$DEFAULT_GIT_USER_EMAIL"
        CURRENT_GIT_USER_EMAIL="$DEFAULT_GIT_USER_EMAIL"
    fi
    
    git config --global core.autocrlf input
    git config --global core.editor vim
    
    log_success "Git 用户配置: $CURRENT_GIT_USER_NAME <$CURRENT_GIT_USER_EMAIL>"
}

# 替换远程仓库 URL
replace_remote_url() {
    local repo_path="$1"
    local old_url="$2"
    local new_url="$3"
    
    if [[ -z "$repo_path" ]]; then
        log_error "请提供仓库路径"
        return 1
    fi
    
    if [[ ! -d "$repo_path/.git" ]]; then
        log_error "不是 Git 仓库: $repo_path"
        return 1
    fi
    
    cd "$repo_path"
    
    local current_url
    current_url=$(git remote get-url origin 2>/dev/null || echo "")
    
    if [[ -n "$old_url" && -n "$new_url" ]]; then
        # 直接替换模式
        if [[ -n "$current_url" ]]; then
            log_info "将远程 URL 从 $old_url 替换为 $new_url"
            git remote set-url origin "$new_url"
            log_success "远程 URL 已更新"
        else
            log_error "仓库没有配置 origin 远程"
        fi
    else
        # 交互模式
        log_info "当前远程 URL: $current_url"
        echo "选择新的协议:"
        echo "1) SSH (git@github.com:user/repo.git)"
        echo "2) HTTPS (https://github.com/user/repo.git)"
        read -rp "请输入选择 (1/2): " protocol_choice
        
        case $protocol_choice in
            1)
                # 转换为 SSH
                if [[ "$current_url" == https://* ]]; then
                    new_url=$(echo "$current_url" | sed -E 's#https://([^/]+)/(.+)#git@\1:\2#')
                    git remote set-url origin "$new_url"
                    log_success "已转换为 SSH: $new_url"
                else
                    log_info "当前已经是 SSH 协议"
                fi
                ;;
            2)
                # 转换为 HTTPS
                if [[ "$current_url" == git@* ]]; then
                    new_url=$(echo "$current_url" | sed -E 's#git@([^:]+):(.+)#https://\1/\2#')
                    git remote set-url origin "$new_url"
                    log_success "已转换为 HTTPS: $new_url"
                else
                    log_info "当前已经是 HTTPS 协议"
                fi
                ;;
            *)
                log_error "无效选择"
                return 1
                ;;
        esac
    fi
}

# 批量处理仓库
batch_process_repos() {
    local base_dir="$1"
    
    if [[ -z "$base_dir" ]]; then
        base_dir="$PWD"
    fi
    
    log_info "在目录 $base_dir 中查找 Git 仓库..."
    
    find "$base_dir" -type d -name ".git" | while read -r git_dir; do
        local repo_dir=$(dirname "$git_dir")
        log_info "处理仓库: $repo_dir"
        
        cd "$repo_dir"
        local current_url=$(git remote get-url origin 2>/dev/null || echo "无")
        log_info "当前远程: $current_url"
        
        replace_remote_url "$repo_dir"
        echo "----------------------------------------"
    done
}

# 用户配置管理菜单
user_management_menu() {
    echo -e "${CYAN}"
    echo "👤 Git 用户配置管理"
    echo "===================="
    echo -e "${NC}"
    echo "1) 显示当前用户配置"
    echo "2) 替换用户和邮箱"
    echo "3) 重置为默认用户配置"
    echo "4) 更新现有仓库的用户信息"
    echo "5) 返回主菜单"
    echo
    
    read -rp "请选择操作 (1-5): " choice
    
    case $choice in
        1) 
            show_git_config
            ;;
        2) 
            replace_git_user
            ;;
        3) 
            reset_git_user_to_default
            ;;
        4) 
            update_existing_repos_author
            ;;
        5) 
            return
            ;;
        *) 
            log_error "无效选择"
            ;;
    esac
    
    echo
    read -rp "按回车键继续..."
    user_management_menu
}

# 主菜单
main_menu() {
    echo -e "${BLUE}"
    echo "🔄 Git 远程仓库管理脚本 - Termux 增强版"
    echo "=========================================="
    echo -e "${NC}"
    echo "👤 当前用户: ${CURRENT_GIT_USER_NAME:-未设置}"
    echo "📧 当前邮箱: ${CURRENT_GIT_USER_EMAIL:-未设置}"
    echo ""
    echo "1) 生成新的 SSH Key"
    echo "2) 配置 SSH 和 Git"
    echo "3) 测试 SSH 连接"
    echo "4) 用户配置管理"
    echo "5) 替换单个仓库远程 URL"
    echo "6) 批量处理目录下的所有仓库"
    echo "7) 显示 SSH 公钥"
    echo "8) 退出"
    echo
    
    read -rp "请选择操作 (1-8): " choice
    
    case $choice in
        1) generate_ssh_key ;;
        2) 
            generate_ssh_key
            configure_ssh
            setup_git_config
            ;;
        3) test_ssh_connection ;;
        4) user_management_menu ;;
        5)
            read -rp "请输入仓库路径: " repo_path
            replace_remote_url "$repo_path"
            ;;
        6)
            read -rp "请输入目录路径 (回车使用当前目录): " base_dir
            batch_process_repos "${base_dir:-$PWD}"
            ;;
        7)
            echo ""
            log_info "SSH 公钥内容:"
            echo "=========================================="
            cat "$SSH_DIR/$KEY_NAME.pub" 2>/dev/null || log_error "SSH 公钥不存在，请先生成密钥"
            echo "=========================================="
            echo ""
            ;;
        8)
            log_success "再见！"
            exit 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
    
    echo
    read -rp "按回车键继续..."
    main_menu
}

# 脚本入口
main() {
    log_info "环境识别: termux"
    log_info "临时目录: $TEMP_DIR"
    log_info "SSH 目录: $SSH_DIR"
    
    check_dependencies
    
    # 创建临时目录
    mkdir -p "$TEMP_DIR"
    
    # 显示当前 Git 配置
    show_git_config
    
    main_menu
}

# 运行主函数
main "$@"
