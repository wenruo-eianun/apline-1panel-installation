#!/bin/sh

# ================================================================================
# 自动 Bash 环境引导程序
# ================================================================================
if [ -z "$BASH_VERSION" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        if command -v apk >/dev/null 2>&1; then
            echo "未检测到 Bash, 正在为 Alpine 系统安装..."
            apk add --no-cache bash
            exec bash "$0" "$@"
        else
            echo "错误: 运行此脚本需要 Bash, 但它未被安装且无法自动安装。" >&2
            echo "请先手动安装 'bash' 再运行此脚本。" >&2
            exit 1
        fi
    fi
fi

# ================================================================================
# 从这里开始，我们保证脚本运行在 Bash 环境下
# ================================================================================
set -e

# --- 全局变量 ---
BASE_CONTAINER_NAME="nexus-node"
IMAGE_NAME="nexus-node:latest"
LOG_DIR="/root/nexus_logs"

# --- 权限检查 ---
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本需要以 root 权限运行。" >&2
    exit 1
fi

#================================================================================
# 兼容性模块: 自动检测并安装依赖
#================================================================================

# 检测包管理器
function detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt";
    elif command -v dnf >/dev/null 2>&1; then echo "dnf";
    elif command -v yum >/dev/null 2>&1; then echo "yum";
    elif command -v pacman >/dev/null 2>&1; then echo "pacman";
    elif command -v zypper >/dev/null 2>&1; then echo "zypper";
    elif command -v apk >/dev/null 2>&1; then echo "apk";
    else echo "unsupported"; fi
}

# 安装脚本运行所需的核心依赖
function install_dependencies() {
    local PKG_MANAGER=$(detect_package_manager)
    if [ "$PKG_MANAGER" = "apk" ]; then
        echo "Alpine 系统: 正在检查并安装核心依赖 (curl, util-linux)..."
        apk add --no-cache curl util-linux
    fi
}

# 检查并安装 Docker (兼容 systemd 和 OpenRC)
function check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "检测到未安装 Docker，正在使用官方脚本安装..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        chmod +x get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        
        echo "启动 Docker 服务并设置开机自启..."
        if command -v systemctl >/dev/null 2>&1; then
            systemctl enable docker >/dev/null 2>&1 || echo "警告: 无法设置 Docker 开机自启。"
            systemctl start docker >/dev/null 2>&1 || echo "警告: 无法启动 Docker 服务。"
        elif command -v rc-update >/dev/null 2>&1; then
            rc-update add docker boot >/dev/null 2>&1 || echo "警告: 无法设置 Docker 开机自启。"
            service docker start >/dev/null 2>&1 || echo "警告: 无法启动 Docker 服务。"
        else
            echo "警告: 未知的初始化系统, 无法自动启动 Docker。请手动操作。"
        fi

        if ! command -v docker >/dev/null 2>&1; then
            echo "错误：Docker 安装失败。"
            exit 1
        fi
        echo "Docker 安装成功！"
    fi
}

# 检查并安装 Node.js/npm/pm2
function check_pm2() {
    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        echo "检测到未安装 Node.js/npm，正在尝试安装..."
        local PKG_MANAGER=$(detect_package_manager)

        case $PKG_MANAGER in
            apt) apt-get update; apt-get install -y nodejs npm ;;
            dnf) dnf install -y nodejs npm ;;
            yum) yum install -y nodejs npm ;;
            pacman) pacman -S --noconfirm nodejs npm ;;
            zypper) zypper install -y nodejs npm ;;
            apk) apk add --no-cache nodejs npm ;;
            *) echo "错误：未检测到支持的包管理器。请手动安装 Node.js 和 npm。"; exit 1 ;;
        esac
        
        if ! command -v node >/dev/null 2>&1; then
            echo "错误：Node.js 安装失败。"
            exit 1
        fi
    fi

    if ! command -v pm2 >/dev/null 2>&1; then
        echo "检测到未安装 pm2，正在通过 npm 全局安装..."
        npm install -g pm2
    fi
}

#================================================================================
# 核心功能模块
#================================================================================

# 构建docker镜像函数
function build_image() {
    WORKDIR=$(mktemp -d)
    cd "$WORKDIR"

    cat > Dockerfile <<EOF
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.kernel.org/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
RUN apt-get update && apt-get install -y curl screen bash && rm -rf /var/lib/apt/lists/*
RUN curl -sSL https://cli.nexus.xyz/ | NONINTERACTIVE=1 sh && ln -sf /root/.nexus/bin/nexus-network /usr/local/bin/nexus-network
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
EOF

    cat > entrypoint.sh <<EOF
#!/bin/bash
set -e
PROVER_ID_FILE="/root/.nexus/node-id"
if [ -z "\$NODE_ID" ]; then echo "错误：未设置 NODE_ID 环境变量"; exit 1; fi
echo "\$NODE_ID" > "\$PROVER_ID_FILE"
echo "使用的 node-id: \$NODE_ID"
if ! command -v nexus-network >/dev/null 2>&1; then echo "错误：nexus-network 未安装或不可用"; exit 1; fi
screen -S nexus -X quit >/dev/null 2>&1 || true
echo "启动 nexus-network 节点..."
screen -dmS nexus bash -c "nexus-network start --node-id \$NODE_ID &>> /root/nexus.log"
sleep 3
if screen -list | grep -q "nexus"; then
    echo "节点已在后台启动。日志文件：/root/nexus.log"
    echo "可以使用 docker logs \$CONTAINER_NAME 查看日志"
else
    echo "节点启动失败，请检查日志。"; cat /root/nexus.log; exit 1
fi
tail -f /root/nexus.log
EOF

    docker build -t "$IMAGE_NAME" .
    cd - && rm -rf "$WORKDIR"
}

# 启动容器
function run_container() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"
    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        echo "检测到旧容器 $container_name，先删除..."
        docker rm -f "$container_name"
    fi
    mkdir -p "$LOG_DIR"
    if [ ! -f "$log_file" ]; then
        touch "$log_file"
        chmod 644 "$log_file"
    fi
    docker run -d --name "$container_name" -v "$log_file":/root/nexus.log -e NODE_ID="$node_id" "$IMAGE_NAME"
    echo "容器 $container_name 已启动！"
}

# 卸载节点
function uninstall_node() {
    local node_id=$1
    local container_name="${BASE_CONTAINER_NAME}-${node_id}"
    local log_file="${LOG_DIR}/nexus-${node_id}.log"
    echo "停止并删除容器 $container_name..."
    docker rm -f "$container_name" 2>/dev/null || echo "容器 $container_name 不存在或已停止。"
    if [ -f "$log_file" ]; then
        echo "删除日志文件 $log_file ..."
        rm -f "$log_file"
    fi
}

# 显示节点列表
function list_nodes() {
    echo "当前节点状态："
    echo "------------------------------------------------------------------------------------------------------------------------"
    printf "%-6s %-20s %-10s %-10s %-10s %-20s %-20s\n" "序号" "节点ID" "CPU使用率" "内存使用" "内存限制" "状态" "启动时间"
    echo "------------------------------------------------------------------------------------------------------------------------"
    
    local all_nodes=($(get_all_nodes))
    for i in "${!all_nodes[@]}"; do
        local node_id=${all_nodes[$i]}
        local container_name="${BASE_CONTAINER_NAME}-${node_id}"
        local container_info=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" $container_name 2>/dev/null)
        
        if [ -n "$container_info" ]; then
            IFS=',' read -r cpu_usage mem_usage mem_perc <<< "$container_info"
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            local created_time=$(docker ps -a --filter "name=$container_name" --format "{{.CreatedAt}}")
            
            printf "%-6d %-20s %-10s %-10s %-10s %-20s %-20s\n" \
                $((i+1)) "$node_id" "$cpu_usage" \
                "$(echo "$mem_usage" | cut -d'/' -f1 | sed 's/ //g')" \
                "$(echo "$mem_usage" | cut -d'/' -f2 | sed 's/ //g')" \
                "$(echo $status | cut -d' ' -f1)" "$created_time"
        else
            local status=$(docker ps -a --filter "name=$container_name" --format "{{.Status}}")
            local created_time=$(docker ps -a --filter "name=$container_name" --format "{{.CreatedAt}}")
            if [ -n "$status" ]; then
                printf "%-6d %-20s %-10s %-10s %-10s %-20s %-20s\n" \
                    $((i+1)) "$node_id" "N/A" "N/A" "N/A" "$(echo $status | cut -d' ' -f1)" "$created_time"
            fi
        fi
    done
    echo "------------------------------------------------------------------------------------------------------------------------"
    read -p "按任意键返回菜单"
}

# 获取所有节点ID
function get_all_nodes() {
    docker ps -a --filter "name=${BASE_CONTAINER_NAME}" --format "{{.Names}}" | sed "s/${BASE_CONTAINER_NAME}-//"
}

# 查看节点日志
function select_node_to_view() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then echo "当前没有节点"; read -p "按任意键返回菜单"; return; fi
    echo "请选择要查看的节点："
    echo "0. 返回主菜单"
    for i in "${!all_nodes[@]}"; do echo "$((i+1)). 节点 ${all_nodes[$i]}"; done
    read -rp "请输入选项(0-${#all_nodes[@]}): " choice
    if [ "$choice" = "0" ]; then return; fi
    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_nodes[@]} ]; then
        local selected_node=${all_nodes[$((choice-1))]}
        echo "查看日志，按 Ctrl+C 退出"
        docker logs -f "${BASE_CONTAINER_NAME}-${selected_node}"
    else
        echo "无效的选项"
    fi
    read -p "按任意键继续"
}

# 批量卸载节点
function batch_uninstall_nodes() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then echo "当前没有节点"; read -p "按任意键返回菜单"; return; fi
    echo "请选择要删除的节点（可多选，输入数字，用空格分隔）："
    echo "0. 返回主菜单"
    for i in "${!all_nodes[@]}"; do echo "$((i+1)). 节点 ${all_nodes[$i]}"; done
    read -rp "请输入选项: " choices
    if [ "$choices" = "0" ]; then return; fi
    read -ra selected_choices <<< "$choices"
    for choice in "${selected_choices[@]}"; do
        if [ "$choice" -ge 1 ] && [ "$choice" -le ${#all_nodes[@]} ]; then
            uninstall_node "${all_nodes[$((choice-1))]}"
        else
            echo "跳过无效选项: $choice"
        fi
    done
    echo "批量卸载完成！"
    read -p "按任意键返回菜单"
}

# 删除全部节点
function uninstall_all_nodes() {
    local all_nodes=($(get_all_nodes))
    if [ ${#all_nodes[@]} -eq 0 ]; then echo "当前没有节点"; read -p "按任意键返回菜单"; return; fi
    read -rp "警告: 此操作将删除所有 ${#all_nodes[@]} 个节点！确定吗？(y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then echo "已取消操作"; read -p "按任意键返回菜单"; return; fi
    for node_id in "${all_nodes[@]}"; do uninstall_node "$node_id"; done
    if [ -d "/root/nexus_scripts" ]; then echo "删除 /root/nexus_scripts 目录..."; rm -rf "/root/nexus_scripts"; fi
    echo "所有节点已删除完成！"
    read -p "按任意键返回菜单"
}

# 批量节点轮换启动
function batch_rotate_nodes() {
    check_pm2
    echo "请输入多个 node-id，每行一个，按 Ctrl+D 结束输入："
    local node_ids=()
    while read -r line; do
        if [ -n "$line" ]; then node_ids+=("$line"); fi
    done < /dev/stdin
    if [ ${#node_ids[@]} -eq 0 ]; then echo "未输入任何 node-id。"; read -p "按任意键继续"; return; fi
    read -rp "请输入每两小时要启动的节点数量（默认：${#node_ids[@]}的一半）: " nodes_per_round
    nodes_per_round=${nodes_per_round:-$(( (${#node_ids[@]} + 1) / 2 ))}
    if ! [[ "$nodes_per_round" =~ ^[0-9]+$ ]] || [ "$nodes_per_round" -lt 1 ]; then echo "无效的节点数量。"; read -p "按任意键继续"; return; fi
    
    local total_nodes=${#node_ids[@]}
    local num_groups=$(( (total_nodes + nodes_per_round - 1) / nodes_per_round ))
    
    echo "停止旧的轮换进程..."
    pm2 delete nexus-rotate 2>/dev/null || true
    echo "开始构建镜像..."
    build_image
    
    local script_dir="/root/nexus_scripts"
    mkdir -p "$script_dir"
    
    for ((group=1; group<=num_groups; group++)); do
        cat > "$script_dir/start_group${group}.sh" <<EOF
#!/bin/bash
set -e
docker ps -a --filter "name=${BASE_CONTAINER_NAME}" --format "{{.Names}}" | xargs -r docker rm -f
EOF
    done
    
    for i in "${!node_ids[@]}"; do
        local node_id=${node_ids[$i]}
        local group_num=$(( i / nodes_per_round + 1 ))
        if [ $group_num -gt $num_groups ]; then group_num=$num_groups; fi
        
        mkdir -p "$LOG_DIR"
        touch "${LOG_DIR}/nexus-${node_id}.log"; chmod 644 "${LOG_DIR}/nexus-${node_id}.log"
        
        echo "echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] 启动节点 $node_id ...\"" >> "$script_dir/start_group${group_num}.sh"
        echo "docker run -d --name \"${BASE_CONTAINER_NAME}-${node_id}\" -v \"${LOG_DIR}/nexus-${node_id}.log\":/root/nexus.log -e NODE_ID=\"$node_id\" \"$IMAGE_NAME\"" >> "$script_dir/start_group${group_num}.sh"
        echo "sleep 30" >> "$script_dir/start_group${group_num}.sh"
    done
    
    cat > "$script_dir/rotate.sh" <<EOF
#!/bin/bash
set -e
while true; do
EOF
    
    for ((group=1; group<=num_groups; group++)); do
        cat >> "$script_dir/rotate.sh" <<EOF
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 启动第${group}组节点..."
    bash "$script_dir/start_group${group}.sh"
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 等待2小时..."
    sleep 7200
EOF
    done
    
    echo "done" >> "$script_dir/rotate.sh"
    chmod +x "$script_dir"/*.sh
    pm2 start "$script_dir/rotate.sh" --name "nexus-rotate"
    pm2 save
    
    echo "节点轮换已启动！使用 'pm2 status' 查看状态。"
    read -p "按任意键返回菜单"
}

# 设置定时清理日志任务
function setup_log_cleanup_cron() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "警告: 未找到 crontab 命令，无法设置自动清理日志任务。"
        return
    fi
    if command -v rc-service >/dev/null 2>&1 && ! rc-service crond status -q 2>/dev/null; then
        echo "正在为 Alpine 启动并启用 crond 服务..."
        rc-update add crond default >/dev/null 2>&1
        rc-service crond start >/dev/null 2>&1
    fi
    local cron_job="0 3 */2 * * find $LOG_DIR -type f -name 'nexus-*.log' -mtime +2 -delete"
    (crontab -l 2>/dev/null | grep -Fv "$cron_job"; echo "$cron_job") | crontab -
    echo "已设置或确认了日志清理定时任务。"
}

# ==================== 新增功能 ====================
# 彻底卸载脚本及所有相关组件
function uninstall_everything() {
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!! 警告 !!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "这是一个非常危险的操作，将彻底从您的系统中移除此脚本及其创建的所有内容。"
    echo
    echo "将执行以下操作："
    echo "  1. 停止并删除所有 Nexus 节点容器。"
    echo "  2. 删除为节点构建的 Docker 镜像 '$IMAGE_NAME'。"
    echo "  3. 删除 PM2 中的 'nexus-rotate' 进程 (如果存在)。"
    echo "  4. 删除所有日志目录 '$LOG_DIR'。"
    echo "  5. 删除轮换任务脚本目录 '/root/nexus_scripts'。"
    echo "  6. 从定时任务(crontab)中移除日志清理条目。"
    echo
    read -rp "您确定要继续吗？此操作无法撤销！(请输入 'yes' 以确认): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "操作已取消。"
        read -p "按任意键返回菜单"
        return
    fi

    echo "-----------------------------------------------------"
    echo "正在开始彻底卸载流程..."
    
    echo "[1/6] 正在停止并删除所有节点容器..."
    docker ps -a --filter "name=${BASE_CONTAINER_NAME}" --format "{{.Names}}" | xargs -r docker rm -f || echo "  -> 没有找到要删除的容器。"

    echo "[2/6] 正在删除 Docker 镜像 '$IMAGE_NAME'..."
    docker rmi -f "$IMAGE_NAME" 2>/dev/null || echo "  -> 没有找到要删除的镜像，或已被删除。"

    if command -v pm2 >/dev/null 2>&1; then
        echo "[3/6] 正在删除 PM2 进程..."
        pm2 delete nexus-rotate 2>/dev/null || echo "  -> 没有找到名为 'nexus-rotate' 的 PM2 进程。"
        pm2 save --force >/dev/null 2>&1 || true
    fi

    echo "[4/6] 正在删除日志目录 '$LOG_DIR'..."
    rm -rf "$LOG_DIR"
    echo "  -> 日志目录已删除。"

    echo "[5/6] 正在删除脚本目录 '/root/nexus_scripts'..."
    rm -rf "/root/nexus_scripts"
    echo "  -> 脚本目录已删除。"

    if command -v crontab >/dev/null 2>&1; then
        echo "[6/6] 正在移除 cron 日志清理任务..."
        (crontab -l 2>/dev/null | grep -v "$LOG_DIR") | crontab -
        echo "  -> cron 任务已移除。"
    fi
    
    echo "-----------------------------------------------------"
    echo "所有相关组件已成功卸载！"
    
    read -rp "是否要删除此管理脚本文件本身 '$0'？(y/N): " delete_self
    if [[ "$delete_self" =~ ^[Yy]$ ]]; then
        echo "正在删除脚本文件..."
        # 这是脚本的最后一条命令，执行后脚本将消失
        rm -- "$0"
        echo "脚本已删除。再见！"
    else
        echo "脚本文件已保留。卸载完成。"
        read -p "按任意键退出。"
    fi
}


#================================================================================
# 主菜单
#================================================================================

install_dependencies
setup_log_cleanup_cron

while true; do
    clear
    echo "脚本由哈哈哈哈编写，eianun修改适配Linux，免费开源，请勿相信收费"
    echo "============== Nexus 多节点管理 (全兼容最终稳定版) =============="
    echo "1. 安装并启动新节点"
    echo "2. 显示所有节点状态"
    echo "3. 批量停止并卸载指定节点"
    echo "4. 查看指定节点日志"
    echo "5. 批量节点轮换启动"
    echo "6. 删除全部节点"
    echo "7. 彻底卸载脚本与全部组件"
    echo "8. 退出"
    echo "======================================================================"

    read -rp "请输入选项(1-8): " choice

    case $choice in
        1)
            check_docker
            read -rp "请输入您的 node-id: " NODE_ID
            if [ -z "$NODE_ID" ]; then
                echo "node-id 不能为空。"
                read -p "按任意键继续"
                continue
            fi
            echo "开始构建镜像并启动容器..."
            build_image
            run_container "$NODE_ID"
            read -p "按任意键返回菜单"
            ;;
        2) list_nodes ;;
        3) batch_uninstall_nodes ;;
        4) select_node_to_view ;;
        5) check_docker; check_pm2; batch_rotate_nodes ;;
        6) uninstall_all_nodes ;;
        7) uninstall_everything; exit 0 ;;
        8) echo "退出脚本。"; exit 0 ;;
        *) echo "无效选项，请重新输入。"; read -p "按任意键继续" ;;
    esac
done
