# AutoGateway

一款基于 iptables + TPROXY 实现的透明网关脚本，支持 IPv6 和智能分流。

## 功能特性

- **透明代理**：基于 iptables 和 TPROXY 实现透明代理，支持 IPv4 和 IPv6
- **智能分流**：自动识别国内外流量，国内流量直连，国外流量走代理
- **DNS 劫持**：自动劫持 DNS 请求以使用本地 DNS 服务器
- **服务化支持**：提供 systemd 服务配置，支持开机自启
- **错误处理**：完善的错误处理机制，脚本执行失败时会及时停止并提示错误信息

## 使用前提

- 系统：Linux、OpenWrt 等 Linux 衍生系统
- 软件：`bash`、`ipset`、`iptables`、`ip6tables`、`TPROXY` 模块
- 权限：root 权限
- 内核配置：
    ```bash
    # 开启 IPv4 转发
    sysctl -w net.ipv4.ip_forward=1
    
    # 开启 IPv6 转发
    sysctl -w net.ipv6.conf.all.forwarding=1
    sysctl -w net.ipv6.conf.default.forwarding=1
    ```
- 目标系统的 12345 端口为透明代理端口（Xray/V2Ray 等代理软件监听此端口）
- 目标系统的 DNS 服务器为非 root 用户运行，并监听 53 端口

## 使用方法

1. 下载项目文件：
    - 从 GitHub 下载项目文件：[AutoGateway](https://github.com/coolb/AutoGateway)
    - 或者使用 `git clone` 命令克隆项目：
      ```bash
      git clone https://github.com/coolb/AutoGateway.git
      ```

2. 上传文件到目标系统：
    - 将项目 `root` 目录下的文件上传到目标系统的 `/root` 目录下
    - 将项目 `etc` 目录下的文件上传到目标系统的 `/etc` 目录下（将 `tproxy.service` 文件上传到 `/etc/systemd/system/` 目录下）

3. 验证脚本执行：
    ```bash
    sudo bash /root/tproxy.sh
    ```

4. 验证透明网关功能是否正常

5. 启动透明网关服务并设置开机自启：
    ```bash
    sudo systemctl enable tproxy.service
    sudo systemctl start tproxy.service
    ```

## 重要文件介绍

- `/root/tproxy.sh`：透明网关配置脚本
- `/etc/systemd/system/tproxy.service`：systemd 服务配置文件
- `/root/CN-ip-cidr.txt`：中国大陆 IP 地址段列表，用于流量分流
- `/root/tailscale-ip-cidr.txt`：Tailscale DERP 服务器 IP 地址段列表，确保 Tailscale 流量直连

## 分流原理

脚本通过 ipset 维护一个中国大陆 IP 地址集合，对于目标地址属于该集合的流量直接放行，其他流量则通过 TPROXY 重定向到代理端口。这样实现了国内外流量的智能分流，提升访问速度并节省代理流量。

## 已知问题

1. 透明网关基于 iptables 实现，遇到第三方软件在启动和运行时清除 iptables 规则，会导致透明网关失效(比如docker)。
2. 脚本添加了 DNS 劫持功能，如果要避开当前脚本对 DNS 的要求，可以把脚本中涉及 53 端口的行注释掉。

