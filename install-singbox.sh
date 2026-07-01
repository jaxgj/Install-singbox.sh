#!/bin/bash
set -euo pipefail

# 颜色常量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Sing-box 一键部署脚本 | Dynv6 固定IP版 ${NC}"
echo -e "${GREEN} Shadowsocks(aes-256-gcm) + Hysteria2 双协议 ${NC}"
echo -e "${GREEN}  基于acme.sh DNS-01验证 | 兼容 Debian 11/12/13 ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# ====================== 交互输入区 ======================
read -p "1. 输入 Dynv6 域名 (例: abc.dynv6.net)：" DOMAIN
while [[ -z "$DOMAIN" ]]; do
    read -p "${RED}域名不能为空，请重新输入：${NC}" DOMAIN
done

read -p "2. 输入 Dynv6 API Token：" DYNV6_TOKEN
while [[ -z "$DYNV6_TOKEN" ]]; do
    read -p "${RED}Token不能为空，DNS-01证书验证依赖该Token，请重新输入：${NC}" DYNV6_TOKEN
done

read -p "3. Shadowsocks TCP 端口 [默认8388]：" SS_PORT
SS_PORT=${SS_PORT:-8388}

read -p "4. Shadowsocks 自定义密码，留空自动随机生成：" SS_PASS
if [[ -z "$SS_PASS" ]]; then
    SS_PASS=$(openssl rand -base64 16 | tr -d '/+=\n')
fi

read -p "5. Hysteria2 UDP 端口 [默认8443]：" HY2_PORT
HY2_PORT=${HY2_PORT:-8443}

read -p "6. Hysteria2 上下行带宽 mbps [默认100]：" BANDWIDTH
BANDWIDTH=${BANDWIDTH:-100}

read -p "7. Hysteria2 自定义密码，留空自动随机生成：" HY2_PASS
if [[ -z "$HY2_PASS" ]]; then
    HY2_PASS=$(openssl rand -base64 24 | tr -d '/+=\n')
fi

echo ""
echo -e "${BLUE}===== 当前配置汇总 =====${NC}"
echo "域名：$DOMAIN"
echo "Dynv6 Token：$DYNV6_TOKEN"
echo "SS端口：$SS_PORT | 加密：aes-256-gcm | 密码：$SS_PASS"
echo "Hy2端口：$HY2_PORT | 密码：$HY2_PASS"
echo "Hy2带宽：${BANDWIDTH} mbps"
echo -e "${BLUE}========================${NC}"
read -p "确认开始部署？[y/N] " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}用户取消部署，脚本退出${NC}"
    exit 0
fi
echo ""

# ====================== 1. 系统依赖安装 ======================
echo -e "${GREEN}[1/7] 更新系统 & 安装依赖组件${NC}"
apt update && apt upgrade -y
apt install -y curl wget vim cron ca-certificates openssl socat
if ! command -v ufw &> /dev/null; then
    echo -e "${YELLOW}未检测到ufw防火墙，自动安装中...${NC}"
    apt install -y ufw
fi

# ====================== 2. 防火墙放行端口 ======================
echo -e "${GREEN}[2/7] 配置防火墙放行端口${NC}"
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${SS_PORT}/tcp
ufw allow ${HY2_PORT}/udp
ufw reload

# ====================== 3. 安装 Sing-box 官方源 ======================
echo -e "${GREEN}[3/7] 安装 Sing-box 官方软件源${NC}"
# 清理历史残留错误源文件，避免格式冲突
rm -f /etc/apt/sources.list.d/sagernet.sources
rm -f /etc/apt/sources.list.d/sagernet.list

mkdir -p /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key | tee /etc/apt/keyrings/sagernet.asc >/dev/null
chmod 644 /etc/apt/keyrings/sagernet.asc
# 使用传统.list格式，全Debian/Ubuntu版本兼容
echo "deb [signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.list
apt update
apt install sing-box -y
sing-box version

# ====================== 4. 安装acme.sh并签发证书 ======================
echo -e "${GREEN}[4/7] 安装acme.sh并通过Dynv6 DNS-01签发证书${NC}"
export DYNV6_TOKEN="${DYNV6_TOKEN}"
CERT_DIR="/etc/ssl/${DOMAIN}"
mkdir -p "${CERT_DIR}"

# 安装acme.sh，已存在则跳过
if [ -f "/root/.acme.sh/acme.sh" ]; then
    echo -e "${YELLOW}检测到已安装acme.sh，跳过安装${NC}"
else
    curl -fsSL https://get.acme.sh | sh -s email=admin@example.com
fi

# 签发证书，已存在则跳过
if [ -f "/root/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.cer" ]; then
    echo -e "${YELLOW}检测到已存在证书，跳过签发步骤${NC}"
else
    /root/.acme.sh/acme.sh --issue --dns dns_dynv6 -d "${DOMAIN}"
fi

# 安装证书到统一目录
# 核心兼容逻辑：服务运行则热重载，未运行则静默跳过，不报错、不中断脚本
/root/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" \
    --key-file "${CERT_DIR}/privkey.pem" \
    --fullchain-file "${CERT_DIR}/fullchain.pem" \
    --reloadcmd "systemctl is-active --quiet sing-box && systemctl reload sing-box || true" || true

# ====================== 5. 证书有效期与自动续期确认 ======================
echo -e "${GREEN}[5/7] 确认证书有效期与自动续期配置${NC}"
echo -e "${YELLOW}当前证书有效期：${NC}"
openssl x509 -in "${CERT_DIR}/fullchain.pem" -dates -noout
echo -e "${YELLOW}自动续期：acme.sh每日凌晨检测，剩余30天自动续签${NC}"

# ====================== 6. 生成 Sing-box 服务端配置 ======================
echo -e "${GREEN}[6/7] 生成 Sing-box 配置文件 /etc/sing-box/config.json${NC}"
tee /etc/sing-box/config.json >/dev/null <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/sing-box.log"
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-server",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "aes-256-gcm",
      "password": "${SS_PASS}",
      "multiplex": {
        "enabled": true,
        "max_connections": 64
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-server",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "password": "${HY2_PASS}",
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "certificate_path": "${CERT_DIR}/fullchain.pem",
        "key_path": "${CERT_DIR}/privkey.pem",
        "alpn": ["h3"]
      },
      "bandwidth": {
        "up": "${BANDWIDTH} mbps",
        "down": "${BANDWIDTH} mbps"
      },
      "obfs": {
        "type": "none"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
sing-box check -c /etc/sing-box/config.json

# ====================== 7. 启动 Sing-box 服务 ======================
echo -e "${GREEN}[7/7] 加载systemd并启动sing-box开机自启${NC}"
systemctl daemon-reload
systemctl enable --now sing-box

# ====================== 输出客户端配置 ======================
clear
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}          部署全部完成！客户端参数汇总        ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

echo -e "${YELLOW}【1. Shadowsocks】${NC}"
echo "服务器地址：${DOMAIN}"
echo "端口：${SS_PORT}"
echo "加密方式：aes-256-gcm"
echo "密码：${SS_PASS}"
echo "多路复用：开启"
SS_LINK="ss://$(echo -n "aes-256-gcm:${SS_PASS}" | base64 -w0)@${DOMAIN}:${SS_PORT}#SS-${DOMAIN}"
echo -e "${BLUE}SS分享链接：${SS_LINK}${NC}"
echo ""

echo -e "${YELLOW}【2. Hysteria2】${NC}"
echo "服务器：${DOMAIN}:${HY2_PORT}"
echo "SNI：${DOMAIN}"
echo "密码：${HY2_PASS}"
echo "传输协议：QUIC/h3"
echo "上行带宽：${BANDWIDTH} mbps"
echo "下行带宽：${BANDWIDTH} mbps"
HY2_LINK="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}#HY2-${DOMAIN}"
echo -e "${BLUE}HY2分享链接：${HY2_LINK}${NC}"
echo ""

echo -e "${YELLOW}【3. 证书与续期】${NC}"
echo "证书存储目录：${CERT_DIR}"
echo "自动续期：acme.sh每日检测，剩余30天自动续签"
echo "续期后自动热重载sing-box，在线用户无感知"
echo ""

echo -e "${GREEN}【4. 服务器维护常用命令】${NC}"
echo "查看运行状态：systemctl status sing-box"
echo "重载配置/证书：systemctl reload sing-box"
echo "实时日志：tail -f /var/log/sing-box.log"
echo "手动续证：/root/.acme.sh/acme.sh --renew -d ${DOMAIN} --force"
echo "查看证书：openssl x509 -in ${CERT_DIR}/fullchain.pem -dates -noout"
echo "端口监听：ss -tulnp | grep sing-box"
echo -e "${GREEN}=============================================${NC}"
