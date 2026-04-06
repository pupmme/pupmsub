# pupmsub

> xboard 节点侧轻量 agent + 本地 sing-box 全功能管理面板

## 特性

- **xboard v2 协议**：通过 xboard v2 与控制面板通信，节点注册、配置拉取、流量上报
- **全协议支持**：VLESS / VMess / Trojan / Shadowsocks / Hysteria2 / TUIC / WireGuard / Naive / SSH …
- **双层配置**：xboard inbound 骨架 + 本地高级参数（uTLS / Reality / SS 插件 / Hysteria2 obfs / Mux）
- **Go 模板 SPA**：Vue 3 + Vuetify CDN，无构建依赖，单二进制输出
- **单核收敛**：pupmsub 管理 sing-box，不双开进程，无端口冲突
- **分层存储**：各配置文件独立 JSON，本地无数据库依赖

## 架构

```
xboard 面板
  │ xboard v2 协议（HMAC-SHA256 签名）
  ▼
pupmsub agent
  ├── network/client.go      ← xboard v2 HTTP + ETag
  ├── service/daemon.go      ← handshake / sync / report / status
  ├── service/generator.go   ← inbound 骨架 + 高级参数 → sing-box.json
  ├── service/singbox.go     ← 进程管理（spawn / monitor / restart）
  ├── db/store.go            ← 分层 JSON 存储
  └── api/server.go          ← REST API + Vue SPA
```

## 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/pupmme/pupmsub/main/install.sh | sudo bash
```

安装脚本会自动：
1. 检测系统架构并下载/编译对应二进制
2. 安装 sing-box（如未安装）
3. 创建 systemd 服务
4. **交互式初始化配置**（API 地址、密钥、Web 面板账号等）
5. 启动服务并输出访问地址

## 手动安装

```bash
# 下载最新 release
curl -L https://github.com/pupmme/pupmsub/releases/latest/download/pupmsub-linux-amd64 -o pupmsub
chmod +x pupmsub
sudo mv pupmsub /usr/local/bin/

# 创建目录
sudo mkdir -p /etc/pupmsub /var/log/pupmsub

# 生成初始配置
sudo pupmsub config init

# 安装 systemd 服务
sudo pupmsub service install
sudo systemctl enable --now pupmsub
```

## 配置

`/etc/pupmsub/config.json`:

```json
{
  "api_host": "https://your-xboard.com",
  "api_key": "your-node-key",
  "node_id": 1,
  "node_type": "sing-box",
  "binary_path": "/usr/local/bin/sing-box",
  "config_path": "/etc/pupmsub/sing-box.json",
  "data_dir": "/etc/pupmsub",
  "web_port": "2053",
  "username": "admin",
  "password": "your-password"
}
```

## 构建

```bash
# Linux amd64 (glibc)
CGO_ENABLED=0 go build -ldflags '-w -s' -o pupmsub .

# Linux amd64 (musl / Alpine)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags '-w -s -extldflags "-static"' -o pupmsub .
```

## 前端

内置 Vue 3 SPA，无构建依赖，浏览器加载 CDN 资源后即可使用。

访问 `http://节点IP:2053`，包含以下视图：
- Dashboard：xboard 连接状态、sing-box 状态、节点信息
- Inbounds：入站协议配置（基础骨架 + 高级参数）
- Outbounds：出站节点配置
- Users：用户列表（只读，来自 xboard）
- Rules：路由规则
- DNS：DNS 配置
- TLS：证书 / ACME / Reality
- Services：附加服务
- Endpoints：规则集
- Settings：节点设置
- Logs：日志查看

## xboard v2 API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v2/server/handshake` | 注册节点 |
| GET | `/api/v2/server/config` | 拉取 inbound 骨架 |
| GET | `/api/v2/server/users` | 拉取用户列表 |
| POST | `/api/v2/server/traffic` | 上报流量 |
| POST | `/api/v2/server/status` | 上报系统状态 |

## License

MIT
