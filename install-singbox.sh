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
echo -e "${GREEN} Sing-box 一键部署脚本 | DNS-01 Dynv6 专用 ${NC}"
echo -e "${GREEN} Shadowsocks2022(AES-256-GCM) + Hysteria2 双协议 ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "${YELLOW}说明：强制使用 Dynv6 DNS-01 申请SSL证书，必须提供Dynv6 Token${NC}"
echo ""

# ====================== 交互输入区 ======================
read -p "1. 输入 Dynv6 域名 (例: abc.dynv6.net)：" DOMAIN
while [[ -z "$DOMAIN" ]]; do
    read -p "${RED}域名不能为空，请重新输入：${NC}" DOMAIN
done

read -p "2. 输入 Dynv6 API Token：" DYNV6_TOKEN
while [[ -z "$DYNV6_TOKEN" ]]; do
    read -p "${RED}Token不能为空，DNS-01依赖该Token，请重新输入：${NC}" DYNV6_TOKEN
done

read -p "3. Shadowsocks TCP 端口 [默认8388]：" SS_PORT
SS_PORT=${SS_PORT:-8388}

read -p "4. Hysteria2 UDP 端口 [默认8443]：" HY2_PORT
HY2_PORT=${HY2_PORT:-8443}

read -p "5. Hysteria2 上下行带宽 mbps [默认100]：" BANDWIDTH
BANDWIDTH=${BANDWIDTH:-100}

read -p "6. Hysteria2 自定义密码，留空自动随机生成：" HY2_PASS
# Hy2密码为空则随机生成32位字符串
if [[ -z "$HY2_PASS" ]]; then
    HY2_PASS=$(head -c 24 /dev/urandom | base64 | tr -d '/+=')
fi

# AES-256-GCM 需要32字节密钥，生成32字节base64
SS_KEY=$(sing-box generate rand 32 --base64 2>/dev/null || sing-box generate rand 32 --base64)

echo ""
echo -e "${BLUE}===== 当前配置汇总 =====${NC}"
echo "域名：$DOMAIN"
echo "Dynv6 Token：$DYNV6_TOKEN"
echo "SS端口：$SS_PORT | 加密：2022-blake3-aes-256-gcm | 密钥：$SS_KEY"
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
echo -e "${GREEN}[1/9] 更新系统 & 安装依赖组件${NC}"
apt update && apt upgrade -y
apt install -y curl wget vim cron ca-certificates certbot ufw openssl

# ====================== 2. 防火墙放行端口 ======================
echo -e "${GREEN}[2/9] 配置防火墙放行端口${NC}"
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow ${SS_PORT}/tcp
ufw allow ${HY2_PORT}/udp
ufw reload

# ====================== 3. 安装 Sing-box 官方源 ======================
echo -e "${GREEN}[3/9] 安装 Sing-box 官方软件源${NC}"
mkdir -p /etc/apt/keyrings
curl -fsSL https://sing-box.app/gpg.key | tee /etc/apt/keyrings/sagernet.asc >/dev/null
chmod 644 /etc/apt/keyrings/sagernet.asc
echo "deb [signed-by=/etc/apt/keyrings/sagernet.asc] https://deb.sagernet.org/ * *" | tee /etc/apt/sources.list.d/sagernet.sources
apt update
apt install sing-box -y
sing-box version

# ====================== 4. Dynv6 DDNS 自动更新脚本 ======================
echo -e "${GREEN}[4/9] 生成 Dynv6 IPv6 动态更新脚本 + 定时任务${NC}"
tee /usr/local/bin/dynv6-update.sh >/dev/null <<EOF
#!/bin/bash
DOMAIN="${DOMAIN}"
TOKEN="${DYNV6_TOKEN}"
LOG="/var/log/dynv6.log"
API="https://dynv6.com/api/update?zone=\$DOMAIN&token=\$TOKEN"
echo "[\$(date '+%Y-%m-%d %H:%M:%S')] 执行IPv6更新" >> \$LOG
IPV6=\$(curl -s -6 https://v6.ident.me)
if [[ -z "\$IPV6" || "\$IPV6" == fe80* ]]; then
    echo "IPv6获取失败" >> \$LOG
    exit 1
fi
curl -s "\$API&ipv6=\$IPV6" >> \$LOG
echo "更新完成，当前IPv6: \$IPV6" >> \$LOG
EOF
chmod +x /usr/local/bin/dynv6-update.sh
# 每5分钟执行一次DDNS更新
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/dynv6-update.sh") | crontab -
# 立即执行一次测试
/usr/local/bin/dynv6-update.sh

# ====================== 5. Dynv6 Certbot DNS-01 Hook ======================
echo -e "${GREEN}[5/9] 生成 DNS-01 证书验证钩子脚本${NC}"
tee /usr/local/bin/dynv6-certbot-hook.sh >/dev/null <<EOF
#!/bin/bash
DOMAIN="${DOMAIN}"
TOKEN="${DYNV6_TOKEN}"
API="https://dynv6.com/api/update?zone=\$DOMAIN&token=\$TOKEN"
if [[ -n "\$CERTBOT_VALIDATION" ]]; then
    curl -s "\$API&txt=\$CERTBOT_VALIDATION"
    sleep 15
else
    curl -s "\$API&txt="
fi
EOF
chmod +x /usr/local/bin/dynv6-certbot-hook.sh

# ====================== 6. DNS-01 申请 SSL 证书 ======================
echo -e "${GREEN}[6/9] 通过 Dynv6 DNS-01 申请 Let's Encrypt 证书${NC}"
certbot certonly --manual --preferred-challenges dns \
    --manual-auth-hook /usr/local/bin/dynv6-certbot-hook.sh \
    --manual-cleanup-hook /usr/local/bin/dynv6-certbot-hook.sh \
    -d ${DOMAIN}

# ====================== 7. 配置证书自动续期 + 重载sing-box ======================
echo -e "${GREEN}[7/9] 配置证书自动续期，续证后热重载sing-box${NC}"
RENEW_FILE="/etc/letsencrypt/renewal/${DOMAIN}.conf"
echo "renew_hook = systemctl reload sing-box" >> ${RENEW_FILE}
systemctl enable --now certbot.timer
certbot renew --dry-run

# ====================== 8. 生成 Sing-box 服务端配置 ======================
echo -e "${GREEN}[8/9] 生成 Sing-box 配置文件 /etc/sing-box/config.json${NC}"
tee /etc/sing-box/config.json >/dev/null <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true,
    "output": "/var/log/sing-box.log"
  },
  "dns": {
    "servers": [
      {"address": "223.5.5.5", "detour": "direct"},
      {"address": "8.8.8.8", "detour": "direct"}
    ]
  },
  "inbounds": [
    {
      "type": "shadowsocks",
      "tag": "ss-server",
      "listen": "::",
      "listen_port": ${SS_PORT},
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SS_KEY}",
      "multiplex": {"enabled": true, "max_streams": 64}
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
        "certificate_path": "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem",
        "key_path": "/etc/letsencrypt/live/${DOMAIN}/privkey.pem",
        "alpn": ["h3"]
      },
      "bandwidth": {
        "up": "${BANDWIDTH} mbps",
        "down": "${BANDWIDTH} mbps"
      },
      "obfs": ""
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
EOF
# 校验配置语法
sing-box check -c /etc/sing-box/config.json

# ====================== 9. 启动 Sing-box 服务 ======================
echo -e "${GREEN}[9/9] 加载systemd并启动sing-box开机自启${NC}"
systemctl daemon-reload
systemctl enable --now sing-box

# ====================== 输出完整客户端配置 & 分享链接 ======================
clear
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}          部署全部完成！客户端参数汇总        ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# ---------------- Shadowsocks 2022 AES-256-GCM ----------------
echo -e "${YELLOW}【1. Shadowsocks 2022】${NC}"
echo "服务器地址：${DOMAIN}"
echo "端口：${SS_PORT}"
echo "加密方式：2022-blake3-aes-256-gcm"
echo "密钥：${SS_KEY}"
echo "多路复用：开启"
# SS标准分享链接
SS_LINK="ss://$(echo -n "2022-blake3-aes-256-gcm:${SS_KEY}" | base64 -w0)@${DOMAIN}:${SS_PORT}#SS-${DOMAIN}"
echo -e "${BLUE}SS分享链接：${SS_LINK}${NC}"
echo ""

# ---------------- Hysteria2 ----------------
echo -e "${YELLOW}【2. Hysteria2】${NC}"
echo "服务器：${DOMAIN}:${HY2_PORT}"
echo "SNI：${DOMAIN}"
echo "密码：${HY2_PASS}"
echo "传输协议：QUIC/h3"
echo "上行带宽：${BANDWIDTH} mbps"
echo "下行带宽：${BANDWIDTH} mbps"
# Hysteria2标准分享链接
HY2_LINK="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}?sni=${DOMAIN}&up=${BANDWIDTH}&down=${BANDWIDTH}#HY2-${DOMAIN}"
echo -e "${BLUE}HY2分享链接：${HY2_LINK}${NC}"
echo ""

# ---------------- Sing-box 客户端最简配置模板 ----------------
echo -e "${YELLOW}【3. Sing-box 客户端最简配置模板】${NC}"
cat <<CLIENT
{
  "dns": {"servers": [{"address": "8.8.8.8"}]},
  "outbounds": [
    {
      "type": "shadowsocks",
      "server": "${DOMAIN}",
      "server_port": ${SS_PORT},
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SS_KEY}",
      "multiplex": {"enabled": true}
    },
    {
      "type": "hysteria2",
      "server": "${DOMAIN}",
      "server_port": ${HY2_PORT},
      "password": "${HY2_PASS}",
      "tls": {"server_name": "${DOMAIN}"},
      "bandwidth": {"up": "${BANDWIDTH} mbps", "down": "${BANDWIDTH} mbps"}
    },
    {"type": "direct", "tag": "direct"}
  ]
}
CLIENT
echo ""

# ---------------- 常用维护命令 ----------------
echo -e "${GREEN}【4. 服务器维护常用命令】${NC}"
echo "查看sing-box运行状态：systemctl status sing-box"
echo "重载配置/证书(不中断连接)：systemctl reload sing-box"
echo "实时日志查看：tail -f /var/log/sing-box.log"
echo "手动强制续SSL证书：certbot renew"
echo "查看证书有效期：certbot certificates"
echo "查看端口监听：ss -tulnp | grep sing-box"
echo "手动更新Dynv6 IPv6：/usr/local/bin/dynv6-update.sh"
echo -e "${GREEN}=============================================${NC}"
