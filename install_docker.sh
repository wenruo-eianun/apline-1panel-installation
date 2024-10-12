#!/bin/bash

# 日志记录函数
log() {
  echo -e "\033[1;32m[$(date '+%Y-%m-%d %H:%M:%S')] $1 \033[0m"
}

# 检查用户是否为 root
if [ "$(id -u)" -ne 0 ]; then
  log "请以 root 用户运行此脚本"
  exit 1
fi

# 获取操作系统信息
. /etc/os-release

install_docker_ubuntu_debian() {
  log "安装 Docker for Ubuntu/Debian 系列"
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    gnupg

  curl -fsSL https://download.docker.com/linux/${ID}/gpg | apt-key add -
  add-apt-repository \
    "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/${ID} \
    $(lsb_release -cs) \
    stable"

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
}

install_docker_centos_fedora_rhel_alma_rocky() {
  log "安装 Docker for CentOS/Fedora/RedHat/Alma/Rocky 系列"
  yum install -y yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum install -y docker-ce docker-ce-cli containerd.io
}

install_docker_alpine() {
  log "安装 Docker for Alpine"
  apk add --update docker openrc
  rc-update add docker boot
}

install_docker_arch() {
  log "安装 Docker for Arch Linux"
  pacman -Syu --noconfirm docker
}

install_docker_kali() {
  log "安装 Docker for Kali Linux"
  apt-get update
  apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
  echo "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io
}

# 根据操作系统选择安装方法
case "$ID" in
  ubuntu|debian)
    install_docker_ubuntu_debian
    ;;
  kali)
    install_docker_kali
    ;;
  centos|fedora|rhel|alma|rocky)
    install_docker_centos_fedora_rhel_alma_rocky
    ;;
  alpine)
    install_docker_alpine
    ;;
  arch)
    install_docker_arch
    ;;
  *)
    log "此脚本不支持您的系统: $ID"
    exit 1
    ;;
esac

# 启动并设置 Docker 开机自启
systemctl start docker
systemctl enable docker

# 验证 Docker 是否正确安装
if docker --version > /dev/null 2>&1; then
  log "Docker 安装成功，版本信息如下："
  docker --version
else
  log "Docker 安装失败，请检查日志"
  exit 1
fi

log "======================= 文弱：安装完成 ======================="
