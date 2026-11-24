# Debian 13 云服务器内核

本仓库提供面向 Debian 13 amd64 的 Linux 7.3.6 自定义内核。Debian 软件包版本为 `7.3.6-2`，启动后 `uname -r` 显示 `7.3.6`。

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
