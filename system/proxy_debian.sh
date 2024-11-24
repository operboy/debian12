#!/bin/bash

# 如果没有参数，显示使用说明
if [ -z "$1" ]; then
    echo "用法："
    echo "  设置代理: curl -fsSL https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/proxy_debian.sh | bash -s '代理地址'"
    echo "  清除代理: curl -fsSL https://raw.githubusercontent.com/operboy/debian12/refs/heads/main/proxy_debian.sh | bash -s 'remove'"
    echo ""
    echo "代理地址格式示例："
    echo "  socks5://用户名:密码@IP:端口"
    echo "  http://用户名:密码@IP:端口"
    exit 1
fi

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请使用 sudo 运行此脚本"
    exit 1
fi

# 配置文件路径
ENVIRONMENT_FILE="/etc/environment"
APT_CONF="/etc/apt/apt.conf.d/proxy.conf"

# 如果是移除代理
if [ "$1" = "remove" ]; then
    # 移除系统代理环境变量
    sed -i '/http_proxy/d' $ENVIRONMENT_FILE
    sed -i '/https_proxy/d' $ENVIRONMENT_FILE
    sed -i '/ftp_proxy/d' $ENVIRONMENT_FILE
    sed -i '/no_proxy/d' $ENVIRONMENT_FILE
    sed -i '/HTTP_PROXY/d' $ENVIRONMENT_FILE
    sed -i '/HTTPS_PROXY/d' $ENVIRONMENT_FILE
    sed -i '/FTP_PROXY/d' $ENVIRONMENT_FILE
    sed -i '/NO_PROXY/d' $ENVIRONMENT_FILE

    # 移除apt代理配置
    rm -f $APT_CONF

    echo "已移除所有代理设置"
    source /etc/environment
    echo "请重新登录终端或执行 'source /etc/environment' 使系统代理设置生效"
    exit 0
fi

# 设置代理
proxy="$1"

# 更新系统环境变量
cat <<EOF >> $ENVIRONMENT_FILE
http_proxy=$proxy
https_proxy=$proxy
ftp_proxy=$proxy
no_proxy="localhost,127.0.0.1,::1"
HTTP_PROXY=$proxy
HTTPS_PROXY=$proxy
FTP_PROXY=$proxy
NO_PROXY="localhost,127.0.0.1,::1"
EOF

# 设置apt代理
cat <<EOF > $APT_CONF
Acquire::http::Proxy "$proxy";
Acquire::https::Proxy "$proxy";
EOF

echo "代理设置已更新："
echo "1. 系统代理配置："
grep -i "proxy" $ENVIRONMENT_FILE

echo -e "\n2. APT代理配置："
cat $APT_CONF

source /etc/environment

echo -e "\n请重新登录终端或执行 'source /etc/environment' 使系统代理设置生效"
