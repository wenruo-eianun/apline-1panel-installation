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

