#!/bin/sh

# 函数用于生成随机字符串
generate_random_string() {
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1
}

# 检查是否已安装dante
if ! command -v danted &> /dev/null; then
    echo "Dante Server未安装。正在安装..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                sudo apt-get update && sudo apt-get install -y dante-server
                ;;
            centos|rhel)
                sudo yum install -y epel-release
                sudo yum install -y dante-server
                ;;
            alpine)
                sudo apk update && sudo apk add dante
                ;;
            *)
                echo "不支持的Linux发行版，请手动安装dante-server。"
                exit 1
                ;;
        esac
    else
        echo "无法确定您的Linux发行版，请手动安装dante-server。"
        exit 1
    fi
fi

# 询问用户输入
read -p "请输入SOCKS5服务器的端口（留空自动生成）: " PORT
read -p "请输入SOCKS5服务器的用户名（留空自动生成）: " USERNAME
read -p "请输入SOCKS5服务器的密码（留空自动生成）: " PASSWORD

# 如果用户输入为空，则自动生成
if [ -z "$PORT" ]; then
    PORT=$(shuf -i 10000-65535 -n 1)
fi

if [ -z "$USERNAME" ]; then
    USERNAME=$(generate_random_string)
fi

if [ -z "$PASSWORD" ]; then
    PASSWORD=$(generate_random_string)
fi

# 创建配置文件
cat << EOF > /etc/danted.conf
logoutput: /var/log/danted.log
internal: eth0 port = $PORT
external: eth0
method: username
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    user: $USERNAME:$PASSWORD
}
EOF

# 设置danted服务
# 对于Alpine Linux，使用rc-update和service命令
if [ "$ID" = "alpine" ]; then
    sudo rc-update add danted default
    sudo service danted start
    sudo service danted status
else
    sudo systemctl enable danted
    sudo systemctl start danted
    sudo systemctl status danted
fi

# 输出节点信息
echo "SOCKS5服务器已成功设置。以下是您的节点信息:"
echo "-------------------------------"
echo "服务器地址: $(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
echo "端口: $PORT"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo "-------------------------------"
echo "请确保防火墙允许$PORT端口的流量通过。"
