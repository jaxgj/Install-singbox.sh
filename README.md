# Singbox\-Dynv6 一键部署脚本

**Shadowsocks2022\(AES\-256\-GCM\) \+ Hysteria2 全自动部署｜Dynv6 IPv6动态域名｜DNS\-01证书验证｜自动SSL续证**

✨ Ubuntu 专用全自动部署方案，支持动态IPv6/固定公网IP，全程交互式、全自动运维、零手动配置。

---

## 📌 项目特性

- **双协议组合**：Shadowsocks2022 高强度 AES\-256\-GCM \+ Hysteria2 HTTP3 高速UDP

- **强制 DNS\-01 证书验证**：不占用80端口，适配所有端口占用场景

- **Dynv6 全自动 DDNS**：每5分钟自动更新公网IPv6解析

- **证书永久自动续期**：续期后热重载 Sing\-box，**不中断连接**

- **智能密码机制**：Hysteria2 留空自动生成高强度密码，SS密钥全自动随机生成

- **完整交互式部署**：自定义域名、端口、带宽、密码

- **官方 Sing\-box APT 安装**：安全稳定、支持后续一键升级

- **自动防火墙放行**：放行所有自定义端口

- **自动输出分享链接**：SS / HY2 标准链接，全客户端通用

---

## 💻 支持系统

- Ubuntu 20\.04 / 22\.04 / 24\.04

- 支持：固定公网IP / 动态IPv6 \+ Dynv6域名

---

## 🚀 一键部署

### 1\. 前置条件

- 拥有 Dynv6 域名 \+ API Token（dynv6\.com 获取）

- 服务器支持公网 IPv6

### 2\. 执行部署

```Plain Text
wget https://raw.githubusercontent.com/jaxgj/singbox-dynv6-deploy/main/install-singbox.sh
chmod +x install-singbox.sh
sudo ./install-singbox.sh
```

### 3\. 交互参数说明

|参数|说明|默认值|
|---|---|---|
|Dynv6 域名|必填，例如 xxx\.dynv6\.net|无|
|Dynv6 Token|必填，用于 DDNS \& DNS\-01 证书|无|
|Shadowsocks 端口|TCP 监听端口|8388|
|Hysteria2 端口|UDP 监听端口|8443|
|带宽限制|上下行带宽|100 mbps|
|HY2 密码|留空自动随机生成高强度密码|随机生成|

---

## 📡 服务加密配置

### Shadowsocks 2022

- 加密套件：`2022-blake3-aes-256-gcm`

- 密钥长度：32bit 高强度密钥

- 传输：TCP \+ 多路复用开启

### Hysteria2

- 传输：QUIC / HTTP3

- TLS：Let’s Encrypt 自动证书

- SNI：自动绑定域名

---

## 📱 客户端支持

部署结束自动输出：

- SS 标准分享链接

- HY2 标准分享链接

- 完整 Sing\-box 客户端配置模板

兼容：Sing\-box、Clash Meta、Shadowrocket、V2RayN、Hysteria 客户端

---

## ⚙️ 常用运维命令

```Plain Text
# 查看运行状态
systemctl status sing-box

# 热重载配置/证书（不断线）
systemctl reload sing-box

# 实时日志
tail -f /var/log/sing-box.log

# 手动续证
certbot renew

# 查看证书信息
certbot certificates

# 手动更新DDNS
/usr/local/bin/dynv6-update.sh
```

---

## 🔄 自动化机制

- **DDNS 动态更新**：每5分钟自动刷新 IPv6 解析

- **证书自动续期**：系统定时检测，到期自动续期

- **续证自动热重载**：无需重启、不掉线

---

## 📁 项目文件结构

```Plain Text
├── install-singbox.sh                # 主部署脚本
├── /etc/sing-box/config.json         # Sing-box 核心配置
├── /usr/local/bin/dynv6-update.sh    # IPv6 DDNS 更新
├── /usr/local/bin/dynv6-certbot-hook.sh # DNS-01 证书钩子
└── /var/log/                         # 日志目录
```

---

## ⚠️ 注意事项

- 本脚本仅支持 **Dynv6 DNS\-01** 验证

- 服务器必须拥有公网 IPv6

- 仅供个人学习测试，请遵守当地法律法规

---

## 📜 免责声明

本项目仅供网络技术学习交流，使用者自行承担使用风险，禁止用于非法网络活动。

> （注：部分内容可能由 AI 生成）
