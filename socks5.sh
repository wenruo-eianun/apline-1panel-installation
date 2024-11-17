#!/bin/bash

# 检查并安装danted
if ! command -v danted &> /dev/null; then
    echo "danted 未安装，正在安装..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian|kali)
                sudo apt-get update && sudo apt-get install -y dante-server
                ;;
            centos|rocky|alma|fedora|redhat)
                sudo yum install -y dante-server
                ;;
            arch)
                sudo pacman -Syu --noconfirm dante
                ;;
            alpine)
                sudo apk update && sudo apk add dante
                ;;
            *)
                echo "无法自动安装，请手动安装dante-server或dante软件包。"
                exit 1
                ;;
        esac
    else
        echo "无法确定系统类型，请手动安装dante-server或dante软件包。"
        exit 1
    fi
fi

# 生成随机端口、用户名和密码
PORT=${1:-$(shuf -i 1025-65535 -n 1)}
USERNAME=${2:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)}
PASSWORD=${3:-$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)}

# 提示用户输入端口、用户名和密码
read -p "请输入SOCKS5服务器的端口（留空自动生成）: " input_port
PORT=${input_port:-$PORT}

read -p "请输入SOCKS5服务器的用户名（留空自动生成）: " input_username
USERNAME=${input_username:-$USERNAME}

read -p "请输入SOCKS5服务器的密码（留空自动生成）: " input_password
PASSWORD=${input_password:-$PASSWORD}

# 配置文件路径
CONF_FILE="/etc/danted.conf"

# 备份原配置文件
sudo cp $CONF_FILE ${CONF_FILE}.bak

# 更新配置文件
sudo sed -i "s/^port\s*=.*/port = $PORT/" $CONF_FILE
sudo sed -i "s/^user\.notprivileged\s*=.*/user.notprivileged = $USERNAME/" $CONF_FILE
sudo sed -i "s/^pass\s*=.*/pass = $PASSWORD/" $CONF_FILE

# 保存配置信息到文件
echo "SOCKS5 Server Port: $PORT" > /root/socks5_config.txt
echo "SOCKS5 Server Username: $USERNAME" >> /root/socks5_config.txt
echo "SOCKS5 Server Password: $PASSWORD" >> /root/socks5_config.txt
echo "配置信息已保存到 /root/socks5_config.txt"

# 启动或重启danted服务
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case $ID in
        ubuntu|debian|kali|fedora|arch|alpine)
            if sudo systemctl is-active --quiet danted; then
                sudo systemctl restart danted
            else
                sudo systemctl start danted
            fi
            sudo systemctl enable danted
            sudo systemctl status danted --no-pager
            ;;
        centos|rocky|alma|redhat)
            if sudo systemctl is-active --quiet danted; then
                sudo systemctl restart danted
            else
                sudo systemctl start danted
            fi
            sudo systemctl enable danted
            sudo systemctl status danted --no-pager
            ;;
        *)
            echo "无法自动启动或重启danted服务，请手动操作。"
            ;;
    esac
else
    echo "无法确定系统类型，请手动启动或重启danted服务。"
fi

echo "danted服务已配置并启动。"
