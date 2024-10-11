让apline系统安装1panle 套娃docker运行 安装脚本以及卸载脚本



###  一键安装指令
在终端中运行以下命令来一键安装 `1Panel`：

```bash
sh <(curl -s https://raw.githubusercontent.com/wenruo-eianun/apline-1panel-installation/main/install_1panel.sh)
```
###  清除相关
```bash
rm -f /etc/init.d/1panel
rm -rf /opt/1panel
rm -f /usr/local/bin/1panel /usr/local/bin/1pctl
```
### 一键卸载指令
一键卸载 `1Panel`：

```bash
sh <(curl -s https://raw.githubusercontent.com/wenruo-eianun/apline-1panel-installation/main/uninstall_1panel.sh)
```
### docker版本1panel
```bash
docker run -d \
    --name 1panel \
    --restart always \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
    -v /opt:/opt \
    -v /root:/root \
    -e TZ=Asia/Shanghai \
    moelin/1panel:latest
```
这个错误提示表示容器名“/1panel”已经被一个现有的容器使用。你可以通过以下步骤解决这个问题：

1. **查看现有容器**：
   使用以下命令查看当前运行的容器及其状态：
   ```sh
   docker ps -a
   ```

2. **停止并删除现有容器**：
   如果确认可以删除该容器，使用以下命令：
   ```sh
   docker stop 1panel
   docker rm 1panel
   ```

3. **重新运行你的容器**：
   现在可以重新运行你的 Docker 命令了：
   ```sh
   docker run -d \
       --name 1panel \
       -p "$PANEL_PORT:$PANEL_PORT" \
       -e PANEL_USERNAME="$PANEL_USERNAME" \
       -e PANEL_PASSWORD="$PANEL_PASSWORD" \
       -e PANEL_ENTRANCE="$PANEL_ENTRANCE" \
       -v "$RUN_BASE_DIR":/data \
       1panel:latest
   ```

如果你不想删除已有容器，可以考虑使用不同的容器名称。

