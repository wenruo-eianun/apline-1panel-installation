#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)
# 系统检测
OS_TYPE=$(uname -s)

function install_dependencies() {
    case "$OS_TYPE" in
        Linux)
            if [ -f /etc/alpine-release ]; then
                apk add --no-cache wget tar
            elif [ -f /etc/debian_version ]; then
                apt update && apt install -y wget tar
            elif [ -f /etc/redhat-release ]; then
                yum install -y wget tar || dnf install -y wget tar
            elif [ -f /etc/centos-release ]; then
                yum install -y wget tar
            elif [ -f /etc/kali.version ]; then
                apt update && apt install -y wget tar
            elif [ -f /etc/arch-release ]; then
                pacman -Sy --noconfirm wget tar
            elif [ -f /etc/almalinux-release ]; then
                dnf install -y wget tar
            elif [ -f /etc/rocky-release ]; then
                dnf install -y wget tar
            else
                echo "不支持的操作系统"
                exit 1
            fi
            ;;
        *)
            echo "不支持的操作系统"
            exit 1
            ;;
    esac
}
function log() {
    message="[1Panel Log]: $1 "
    case "$1" in
        *"失败"*|*"错误"*|*"请使用 root 或 sudo 权限运行此脚本"*)
            echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"成功"*)
            echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *"忽略"*|*"跳过"*)
            echo -e "${YELLOW}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
        *)
            echo -e "${BLUE}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/install.log
            ;;
    esac
}

echo
cat << EOF
w       w  eeeee  n     n  rrrrr   u     u  ooooo  
w   w   w  e      nn    n  r   r   u     u  o   o  
w w w w w  eeeee  n n   n  rrrrr   u     u  o   o  
 w       w  e      n  n  n  r  r    u   u   o   o  
 w       w  eeeee  n     n  r   r    uuu     ooooo  

EOF

log "======================= 开始安装 ======================="

function Check_Root() {
    if [ "$EUID" -ne 0 ]; then
        log "请使用 root 或 sudo 权限运行此脚本"
        exit 1
    fi
}

function Prepare_System() {
    if command -v 1panel >/dev/null 2>&1; then
        log "1Panel Linux 服务器运维管理面板已安装，请勿重复安装"
        exit 1
    fi
}
function Download_1Panel() {
    log "下载 1Panel 离线安装包..."
    wget -O /tmp/1panel-v1.10.18-lts-linux-amd64.tar.gz https://github.com/wenruo-eianun/apline-1panel-installation/releases/download/1.0/1panel-v1.10.18-lts-linux-amd64.tar.gz
    if [ $? -eq 0 ]; then
        log "下载完成"
    else
        log "下载失败"
        exit 1
    fi

    log "解压 1Panel 离线安装包..."
    tar -xzvf /tmp/1panel-v1.10.18-lts-linux-amd64.tar.gz -C /tmp
    if [ $? -eq 0 ]; then
        log "解压完成"
    else
        log "解压失败"
        exit 1
    fi

    local install_dir="/tmp/1panel-v1.10.18-lts-linux-amd64"
    
    if [ -d "$install_dir" ]; then
        log "授予 install.sh 执行权限..."
        chmod +x "$install_dir/install.sh"
        if [ $? -eq 0 ]; then
            log "权限授予成功"
        else
            log "权限授予失败"
            exit 1
        fi
    else
        log "安装目录不存在：$install_dir"
        exit 1
    fi
}


function Set_Dir() {
    read -t 120 -p "设置 1Panel 安装目录（默认为/opt）：" PANEL_BASE_DIR
    if [ -z "$PANEL_BASE_DIR" ]; then
        PANEL_BASE_DIR=/opt
    fi

    if [ ! -d "$PANEL_BASE_DIR" ]; then
        mkdir -p "$PANEL_BASE_DIR"
        log "您选择的安装路径为 $PANEL_BASE_DIR"
    fi
}

function Install_Docker() {
    if command -v docker >/dev/null 2>&1; then
        log "检测到 Docker 已安装，跳过安装步骤"
        log "启动 Docker "
        rc-service docker start 2>&1 | tee -a "${CURRENT_DIR}"/install.log
    else
        log "... 安装 Docker"
        apk add --no-cache docker
        rc-update add docker default
        rc-service docker start 2>&1 | tee -a "${CURRENT_DIR}"/install.log
    fi
}

function Set_Port() {
    DEFAULT_PORT=$(shuf -i 10000-65535 -n 1)

    while true; do
        read -p "设置 1Panel 端口（默认为$DEFAULT_PORT）：" PANEL_PORT

        if [ -z "$PANEL_PORT" ]; then
            PANEL_PORT=$DEFAULT_PORT
        fi

        if ! [[ "$PANEL_PORT" =~ ^[1-9][0-9]{0,4}$ && "$PANEL_PORT" -le 65535 ]]; then
            log "错误：输入的端口号必须在 1 到 65535 之间"
            continue
        fi

        if ss -tlun | grep -q ":$PANEL_PORT "; then
            log "端口$PANEL_PORT被占用，请重新输入..."
            continue
        fi

        log "您设置的端口为：$PANEL_PORT"
        break
    done
}

function Set_Firewall() {
    if command -v iptables >/dev/null 2>&1; then
        log "防火墙开放 $PANEL_PORT 端口"
        iptables -A INPUT -p tcp --dport "$PANEL_PORT" -j ACCEPT
        iptables-save > /etc/iptables/rules.v4
    else
        log "未检测到 iptables，无法设置防火墙规则"
    fi
}

function Set_Entrance() {
    DEFAULT_ENTRANCE=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        read -p "设置 1Panel 安全入口（默认为$DEFAULT_ENTRANCE）：" PANEL_ENTRANCE
        if [ -z "$PANEL_ENTRANCE" ]; then
            PANEL_ENTRANCE=$DEFAULT_ENTRANCE
        fi

        if [[ ! "$PANEL_ENTRANCE" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
            log "错误：面板安全入口仅支持字母、数字、下划线，长度 3-30 位"
            continue
        fi

        log "您设置的面板安全入口为：$PANEL_ENTRANCE"
        break
    done
}

function Set_Username() {
    DEFAULT_USERNAME=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        read -p "设置 1Panel 面板用户（默认为$DEFAULT_USERNAME）：" PANEL_USERNAME

        if [ -z "$PANEL_USERNAME" ]; then
            PANEL_USERNAME=$DEFAULT_USERNAME
        fi

        if [[ ! "$PANEL_USERNAME" =~ ^[a-zA-Z0-9_]{3,30}$ ]]; then
            log "错误：面板用户仅支持字母、数字、下划线，长度 3-30 位"
            continue
        fi

        log "您设置的面板用户为：$PANEL_USERNAME"
        break
    done
}

function passwd() {
    charcount='0'
    reply=''
    while :; do
        char=$(stty -cbreak -echo; dd if=/dev/tty bs=1 count=1 2>/dev/null; stty -cbreak echo)
        case $char in
        "$(printenv '\000')")
            break
            ;;
        "$(printf '\177')" | "$(printf '\b')")
            if [ $charcount -gt 0 ]; then
                printf '\b \b'
                reply="${reply%?}"
                charcount=$((charcount - 1))
            else
                printf ''
            fi
            ;;
        "$(printf '\033')") ;;
        *)
            printf '*'
            reply="${reply}${char}"
            charcount=$((charcount + 1))
            ;;
        esac
    done
    printf '\n' >&2
}

function Set_Password() {
    DEFAULT_PASSWORD=$(cat /dev/urandom | head -n 16 | md5sum | head -c 10)

    while true; do
        log "设置 1Panel 面板密码（默认为$DEFAULT_PASSWORD）："
        passwd
        PANEL_PASSWORD=$reply
        if [ -z "$PANEL_PASSWORD" ]; then
            PANEL_PASSWORD=$DEFAULT_PASSWORD
        fi

        if [[ ! "$PANEL_PASSWORD" =~ ^[a-zA-Z0-9_!@#$%*,.?]{8,30}$ ]]; then
            log "错误：面板密码仅支持字母、数字、特殊字符（!@#$%*_,.?），长度 8-30 位"
            continue
        fi

        break
    done
}

function Init_Panel() {
    log "配置 1Panel Service"

    RUN_BASE_DIR=$PANEL_BASE_DIR/1panel
    mkdir -p "$RUN_BASE_DIR"
    rm -rf "$RUN_BASE_DIR:?/*"

    # 离线安装 - 将文件从 /tmp/1panel-v1.10.18-lts-linux-amd64 拷贝到目标目录
    cp /tmp/1panel-v1.10.18-lts-linux-amd64/1panel /usr/local/bin && chmod +x /usr/local/bin/1panel
    cp /tmp/1panel-v1.10.18-lts-linux-amd64/1pctl /usr/local/bin && chmod +x /usr/local/bin/1pctl

    # 配置面板
    sed -i -e "s#BASE_DIR=.*#BASE_DIR=${PANEL_BASE_DIR}#g" /usr/local/bin/1pctl
    sed -i -e "s#ORIGINAL_PORT=.*#ORIGINAL_PORT=${PANEL_PORT}#g" /usr/local/bin/1pctl
    sed -i -e "s#ENTRANCE=.*#ENTRANCE=${PANEL_ENTRANCE}#g" /usr/local/bin/1pctl
    sed -i -e "s#USERNAME=.*#USERNAME=${PANEL_USERNAME}#g" /usr/local/bin/1pctl
    sed -i -e "s#PASSWORD=.*#PASSWORD=${PANEL_PASSWORD}#g" /usr/local/bin/1pctl

    log "面板配置完成"
    log "使用 Docker 启动 1Panel"

    docker run -d \
        --name 1panel \
        -p "$PANEL_PORT:$PANEL_PORT" \
        -e PANEL_USERNAME="$PANEL_USERNAME" \
        -e PANEL_PASSWORD="$PANEL_PASSWORD" \
        -e PANEL_ENTRANCE="$PANEL_ENTRANCE" \
        -v "$RUN_BASE_DIR":/data \
        1panel:latest
}

Check_Root
Prepare_System
Set_Dir
Install_Docker
Set_Port
Set_Firewall
Set_Entrance
Set_Username
Set_Password
Init_Panel

log "======================= 安装完成 ======================="
