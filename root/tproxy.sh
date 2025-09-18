#!/usr/bin/env bash
# iptables + xray 透明代理网关（改进版：错误停止 + 详细提示）
# 参考: https://xtls.github.io/document/level-2/tproxy.html

set -euo pipefail  # 任何命令失败、未定义变量、管道中出错都会导致脚本退出
# -------------------------------
# 工具函数：输出错误并退出
# -------------------------------
error_exit() {
    echo "[错误] $1" >&2
    exit 1
}

# -------------------------------
# 1. 清理 IPv4 相关旧规则
# -------------------------------

echo "[步骤] 清理旧的 IPv4 规则..."

# 删除 fwmark 规则（允许失败，规则可能不存在）
ip rule del fwmark 1 table 100 2>/dev/null || true

# 清空 mangle 表和删除自定义链 XRAY（允许链不存在）
iptables -t mangle -F 2>/dev/null || true
iptables -t mangle -X XRAY 2>/dev/null || true

# 设置策略路由
if ! ip route flush table 100 2>/dev/null; then
    echo "[提示] 清理 IPv4 路由表 100 失败或表不存在，继续..."
fi

if ! ip rule add fwmark 1 table 100; then
    error_exit "添加 IPv4 规则 fwmark 1 table 100 失败"
fi

if ! ip route add local 0.0.0.0/0 dev lo table 100; then
    error_exit "添加 IPv4 路由 local 0.0.0.0/0 dev lo table 100 失败"
fi

# -------------------------------
# 2. 清理 IPv6 相关旧规则
# -------------------------------

echo "[步骤] 清理旧的 IPv6 规则..."

ip -6 rule del fwmark 1 table 100 2>/dev/null || true
ip6tables -t mangle -F 2>/dev/null || true
ip6tables -t mangle -X XRAY6 2>/dev/null || true

ip -6 route flush table 100 2>/dev/null || true

if ! ip -6 rule add fwmark 1 table 100; then
    error_exit "添加 IPv6 规则 fwmark 1 table 100 失败"
fi

if ! ip -6 route add local ::/0 dev lo table 100; then
    error_exit "添加 IPv6 路由 local ::/0 dev lo table 100 失败"
fi

# -------------------------------
# 3. 创建/清理 IPv6 的 XRAY6 链
# -------------------------------

echo "[步骤] 配置 IPv6 TProxy 规则..."

ip6tables -t mangle -N XRAY6 2>/dev/null || true
ip6tables -t mangle -F XRAY6 2>/dev/null || true

# -------------------------------
# 4. 处理 ipset（国内 IP、Tailscale DERP）
# -------------------------------

echo "[步骤] 配置 ipset（国内 IP 等）..."

ipset create cn-ipv4 hash:net family inet 2>/dev/null || true
ipset flush cn-ipv4 2>/dev/null || true

# 加载国内 IP 列表
if [[ -f "/root/CN-ip-cidr.txt" ]]; then
    while read -r line; do
        if [[ -n "$line" ]]; then
            if ! ipset add cn-ipv4 "$line"; then
                echo "[警告] ipset 添加 CN IP 失败: $line"
            fi
        fi
    done < /root/CN-ip-cidr.txt
else
    error_exit "未找到国内 IP 列表文件：/root/CN-ip-cidr.txt"
fi

# 加载 Tailscale DERP IP 列表
if [[ -f "/root/tailscale-ip-cidr.txt" ]]; then
    while read -r line; do
        if [[ -n "$line" ]]; then
            if ! ipset add cn-ipv4 "$line"; then
                echo "[警告] ipset 添加 Tailscale DERP IP 失败: $line"
            fi
        fi
    done < /root/tailscale-ip-cidr.txt
else
    echo "[提示] 未找到 Tailscale DERP IP 文件：/root/tailscale-ip-cicr.txt，跳过"
fi

# -------------------------------
# 5. IPv6 TProxy 规则
# -------------------------------

echo "[步骤] 配置 IPv6 透明代理规则..."

ip6tables -t mangle -A XRAY6 -d ::1/128 -j RETURN
ip6tables -t mangle -A XRAY6 -d fc00::/7 -j RETURN
ip6tables -t mangle -A XRAY6 -d fe80::/10 -j RETURN
ip6tables -t mangle -A XRAY6 -p udp --dport 53 -j RETURN
ip6tables -t mangle -A XRAY6 -p tcp --dport 53 -j RETURN
ip6tables -t mangle -A XRAY6 -p udp --dport 41641 -j RETURN
ip6tables -t mangle -A XRAY6 -m mark --mark 0xff -j RETURN
ip6tables -t mangle -A XRAY6 -p udp -j TPROXY --on-ip ::1 --on-port 12345 --tproxy-mark 1
ip6tables -t mangle -A XRAY6 -p tcp -j TPROXY --on-ip ::1 --on-port 12345 --tproxy-mark 1
ip6tables -t mangle -A PREROUTING -j XRAY6 || error_exit "应用 IPv6 PREROUTING 规则失败"

# -------------------------------
# 6. IPv4 TProxy 规则
# -------------------------------

echo "[步骤] 配置 IPv4 透明代理规则..."

iptables -t mangle -N XRAY 2>/dev/null || true
iptables -t mangle -F XRAY

iptables -t mangle -A XRAY -d 127.0.0.1/32 -j RETURN
iptables -t mangle -A XRAY -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY -d 255.255.255.255/32 -j RETURN
iptables -t mangle -A XRAY -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A XRAY -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 100.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY -d 148.135.107.62/32 -j RETURN
iptables -t mangle -A XRAY -p udp --dport 41641 -j RETURN
iptables -t mangle -A XRAY -m set --match-set cn-ipv4 dst -j RETURN
# DNS规则：SmartDNS进程绕过透明代理
#iptables -t mangle -A XRAY -m owner --uid-owner root -p udp --dport 53 -j RETURN
#iptables -t mangle -A XRAY -m owner --uid-owner root -p tcp --dport 53 -j RETURN
iptables -t mangle -A XRAY -m mark --mark 0xff -j RETURN
iptables -t mangle -A XRAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1
iptables -t mangle -A XRAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port 12345 --tproxy-mark 1

# SmartDNS owner规则（在OUTPUT链中，避免PREROUTING错误）
iptables -t mangle -A OUTPUT -m owner --uid-owner root -p udp --dport 53 -j RETURN
iptables -t mangle -A OUTPUT -m owner --uid-owner root -p tcp --dport 53 -j RETURN

if ! iptables -t mangle -A PREROUTING -j XRAY; then
    error_exit "应用 IPv4 PREROUTING 规则失败"
fi


# -------------------------------
# 7. IPv4 发转规则

# -------------------------------
# 8. DNS劫持规则（在NAT表中）
# -------------------------------

echo "[步骤] 配置DNS劫持规则..."
# 清理旧的DNS劫持规则
iptables -t nat -D OUTPUT -p udp --dport 53 -m owner ! --uid-owner root -j REDIRECT --to-ports 53 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 53 -m owner ! --uid-owner root -j REDIRECT --to-ports 53 2>/dev/null || true
# 添加DNS劫持规则：非root用户的DNS请求重定向到本地53端口
iptables -t nat -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner root -j REDIRECT --to-ports 53 || error_exit "应用DNS UDP劫持规则失败"
iptables -t nat -A OUTPUT -p tcp --dport 53 -m owner ! --uid-owner root -j REDIRECT --to-ports 53 || error_exit "应用DNS TCP劫持规则失败"

# IPv6 DNS劫持规则
echo "[信息] 配置IPv6 DNS劫持..."
ip6tables -t nat -A OUTPUT -p udp --dport 53 -m owner ! --uid-owner root -j REDIRECT --to-ports 53 2>/dev/null || echo "[警告] IPv6 DNS劫持可能不支持"
# -------------------------------

echo "[步骤] IPv4 发转规则..."
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -o eth0 -j MASQUERADE || error_exit "应用 IPv4 发转规则失败"


# -------------------------------
# 9. 成功提示
# -------------------------------

echo "[✅ 成功] 透明代理规则加载完成，支持多次安全执行"