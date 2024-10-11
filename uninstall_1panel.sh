#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

CURRENT_DIR=$(
    cd "$(dirname "$0")" || exit
    pwd
)

function log() {
    message="[1Panel Uninstall Log]: $1 "
    if [[ "$1" == *"成功"* ]]; then
        echo -e "${GREEN}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/uninstall.log
    else
        echo -e "${RED}${message}${NC}" 2>&1 | tee -a "${CURRENT_DIR}"/uninstall.log
    fi
}

log "======================= 开始卸载 ======================="

function Check_Container() {
    if [ "$(docker ps -q -f name=1panel)" ]; then
        log "检测到 1Panel 容器正在运行，准备停止并删除..."
        docker stop 1panel
        docker rm 1panel
        log "1Panel 容器已停止并删除"
    else
        log "未找到 1Panel 容器"
    fi
}

function Remove_Docker_Image() {
    if [ "$(docker images -q 1panel:latest)" ]; then
        log "删除 1Panel Docker 镜像..."
        docker rmi 1panel:latest
        log "1Panel Docker 镜像已删除"
    else
        log "未找到 1Panel Docker 镜像"
    fi
}

function Remove_Files() {
    log "删除 1Panel 安装目录..."
    rm -rf /opt/1panel
    log "1Panel 安装目录已删除"
}

Check_Container
Remove_Docker_Image
Remove_Files

log "======================= 卸载完成 ======================="
