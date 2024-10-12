#!/bin/bash

# 日志记录函数
log() {
  echo -e "\033[1;31m[$(date '+%Y-%m-%d %H:%M:%S')] $1 \033[0m"
}

# 检查用户是否为 root
if [ "$(id -u)" -ne 0 ]; then
  log "请以 root 用户运行此脚本"
  exit 1
fi

# 获取操作系统信息
. /etc/os-release

uninstall_docker_ubuntu_debian() {
  log "卸载 Docker for Ubuntu/Debian 系列"
  apt-get purge -y docker-ce docker-ce-cli containerd.io
  apt-get autoremove -y --purge
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
}

uninstall_docker_centos_fedora_rhel_alma_rocky() {
  log "卸载 Docker for CentOS/Fedora/RedHat/Alma/Rocky 系列"
  yum remove -y docker-ce docker-ce-cli containerd.io
  yum autoremove -y
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
}

uninstall_docker_alpine() {
  log "卸载 Docker for Alpine"
  rc-update del docker boot
  apk del docker
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
}

uninstall_docker_arch() {
  log "卸载 Docker for Arch Linux"
  pacman -Rns --noconfirm docker
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
}

uninstall_docker_kali() {
  log "卸载 Docker for Kali Linux"
  apt-get purge -y docker-ce docker-ce-cli containerd.io
  apt-get autoremove -y --purge
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
}

# 根据操作系统选择卸载方法
case "$ID" in
  ubuntu|debian)
    uninstall_docker_ubuntu_debian
    ;;
  kali)
    uninstall_docker_kali
    ;;
  centos|fedora|rhel|alma|rocky)
    uninstall_docker_centos_fedora_rhel_alma_rocky
    ;;
  alpine)
    uninstall_docker_alpine
    ;;
  arch)
    uninstall_docker_arch
    ;;
  *)
    log "此脚本不支持您的系统: $ID"
    exit 1
    ;;
esac

log "文弱：Docker 已卸载，并清理了所有相关文件。"
