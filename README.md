# Singbox-Dynv6 一键部署脚本
Shadowsocks2022(AES-256-GCM) + Hysteria2 全自动部署｜Dynv6 IPv6动态域名｜DNS-01证书验证｜自动SSL续证

✨ Debian / Ubuntu 全系列全自动部署方案，支持动态IPv6/固定公网IP，全程交互式、全自动运维、零手动配置。

---

## 📌 项目特性
- **双协议组合**：Shadowsocks2022 高强度 AES-256-GCM + Hysteria2 HTTP3 高速UDP
- **强制 DNS-01 证书验证**：不占用80端口，适配所有端口占用场景
- **Dynv6 全自动 DDNS**：每5分钟自动更新公网IPv6解析
- **证书永久自动续期**：续期后热重载 Sing-box，**不中断连接**
- **智能密码机制**：Hysteria2 留空自动生成高强度密码，SS密钥全自动随机生成
- **完整交互式部署**：自定义域名、端口、带宽、密码
- **官方 Sing-box APT 安装**：安全稳定、支持后续一键升级
- **自动防火墙处理**：VPS未预装ufw会自动安装，一键放行所有自定义端口
- **自动输出分享链接**：SS / HY2 标准链接，全客户端通用
- **兼容 Debian13 新APT密钥规范**：无apt-key弃用警告

---

## 💻 支持系统
- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 (Bullseye) / Debian 12 (Bookworm) / Debian 13 (Trixie)
- 网络要求：服务器支持公网 IPv6（固定IP/动态IPv6均可）
- 适配纯净无防火墙全新VPS，自动安装ufw

---

## 🚀 一键部署
### 1. 前置条件
1. 注册 [Dynv6](https://dynv6.com)，创建域名并获取 API Token
2. 服务器拥有公网IPv6网络

### 2. 一键执行部署脚本
```bash
wget https://raw.githubusercontent.com/jaxgj/Install-singbox.sh/main/install-singbox.sh
chmod +x install-singbox.sh
sudo ./install-singbox.sh
