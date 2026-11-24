# Debian 13 云服务器内核

本仓库提供面向 Debian 13 amd64 的 Linux 7.3.6 自定义内核。Debian 软件包版本为 `7.3.6-2`，启动后 `uname -r` 显示 `7.3.6`。

## Debian / Ubuntu 一键安装与清理

支持使用 APT 和 initramfs 的 amd64 主机，需要独立内核。UEFI 主机须关闭 Secure Boot。已在 Debian 13 云实例上实际启动，Ubuntu 尚未进行实机启动测试。

用有权访问此私有仓库的 GitHub CLI 账号登录后，执行以下命令。脚本使用当前账号下载，安装时通过 sudo 提权。

```sh
gh release download v7.3.6-2 -R YJVIst/linux-kernel-binaries -p install-kernel.sh && bash ./install-kernel.sh install --cleanup
```

脚本校验两个 Debian 包，安装内核及头文件，检查 initrd，并在使用 GRUB 时更新菜单。请通过主机引导器启动新内核。省略 `--cleanup` 可仅安装。离线安装可使用 `bash ./install-kernel.sh install --from /path/to/debs`。

`--cleanup` 会预约一次 systemd 开机任务，核对运行内核的版本及构建标识后清理。它保留安装时运行的内核和最新一个带 initrd 的回退内核，跳过标记为 hold 的内核组。仅有一个旧内核时，该版本将保留。版本专用的映像、模块和头文件按软件包名清理，共用头文件和发行版元包会保留。手动预览用 `bash ./install-kernel.sh list-old`，新内核启动后可用 `bash ./install-kernel.sh clean` 确认并执行。

## 下载与校验

[下载 v7.3.6-2](https://github.com/YJVIst/linux-kernel-binaries/releases/tag/v7.3.6-2)。安装内核请选择 `linux-image` 软件包，其中包含内核和配套模块。需要编译第三方模块时，同时下载 `linux-headers` 软件包。独立的 `vmlinuz`、构建配置和 TCP 补丁也随版本提供。

下载全部发布附件后，在下载目录执行 `sha256sum -c SHA256SUMS`。如果仅下载两个 Debian 包和校验清单，可执行以下命令校验并安装。

```sh
grep '  linux-.*\.deb$' SHA256SUMS | sha256sum -c - &&
sudo apt install ./linux-image-7.3.6_7.3.6-2_amd64.deb ./linux-headers-7.3.6_7.3.6-2_amd64.deb
```

## 网络配置与测试

默认 TCP 拥塞控制算法为 BBR，默认排队规则为 fq，MPTCP 默认启用。TCP 接收缓冲区可按连接自动调节。移植的 Cloudflare 补丁以 6 MiB 为接收队列折叠阈值，可通过 `net.ipv4.tcp_collapse_max_bytes` 调整。[Cloudflare 原始补丁](https://github.com/cloudflare/linux/blob/master/patches/0014-add-a-sysctl-to-enable-disable-tcp_collapse-logic.patch)

此版本已在关闭 Secure Boot 的 Debian 13 amd64 云实例上启动，通过 SSH 双向传输、MPTCP 路径切换和 TCP 队列折叠测试。内核映像未签署 Secure Boot 签名。
