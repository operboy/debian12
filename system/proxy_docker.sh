#!/bin/bash

# 如果没有参数，显示使用说明
if [ -z "$1" ]; then
    echo "用法："
    echo "  设置代理: curl -fsSL https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/proxy_docker.sh | bash -s '代理地址'"
    echo "  清除代理: curl -fsSL https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/proxy_docker.sh | bash -s 'remove'"
    echo "  不用代理: curl -fsSL https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/proxy_docker.sh | bash -s 'none'"
    echo ""
    echo "代理地址格式示例："
    echo "  socks5://用户名:密码@IP:端口"
    exit 1
fi

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 sudo 运行此脚本"
    exit 1
fi

# 配置文件路径
PROXY_CONF="/etc/systemd/system/docker.service.d/http-proxy.conf"

# 如果是移除代理
if [ "$1" = "remove" ]; then
    rm -f "$PROXY_CONF"
    systemctl daemon-reload
    systemctl restart docker
    echo "已移除Docker代理配置"
    exit 0
fi

# 创建配置目录
mkdir -p /etc/systemd/system/docker.service.d/

# 如果是设置无代理模式
if [ "$1" = "none" ]; then
    cat <<EOF > "$PROXY_CONF"
[Service]
Environment="NO_PROXY=*"
EOF
else
    # 设置代理
    cat <<EOF > "$PROXY_CONF"
[Service]
Environment="HTTP_PROXY=$1"
Environment="HTTPS_PROXY=$1"
Environment="NO_PROXY=localhost,127.0.0.1,::1"
EOF
fi

# 重启Docker服务
systemctl daemon-reload
systemctl restart docker

echo "Docker代理配置已更新，当前配置："
cat "$PROXY_CONF"