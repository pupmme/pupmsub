# pupmsub — SPEC.md

## 1. 定位

**pupmsub** = xboard 节点 agent + 本地 sing-box 全功能管理面板。

- **xboard**：只提供基础连接信息（protocol / uuid / port）和用户增量（who changed）
- **pupmsub**：管理 sing-box 全部高级参数（uTLS / hysteria2 obfs / ss plugin / reality / mux / etc）
- **xboard inbound 配置**：仅作为 sing-box inbound 的**数据源骨架**，高级参数由本地覆盖/扩展

> xboard 管「基础连接」，pupmsub 管「底层怎么配」

---

## 2. 系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                          xboard 面板                          │
│                  (只下发 inbound 骨架 + 用户变更)              │
└──────────────────────────┬──────────────────────────────────┘
                            │  xboard v2 协议（最小化）
                            │  handshake → 拿 xboard inbound 骨架
                            │  users     → 拿用户变更增量
                            │  traffic   → 静默上报（透明）
                            │  status    → 系统状态
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                          pupmsub agent                        │
│                                                              │
│  network/client.go      ← xboard v2 HTTP + HMAC-SHA256       │
│  service/daemon.go      ← handshake / sync / report / status │
│  service/singbox.go      ← 进程管理                          │
│  service/generator.go    ← 合并：                           │
│                             xboard inbound 骨架（tag/port/type）│
│                             + 节点高级设置（uTLS/reality/obfs）│
│                             → 完整 sing-box.json              │
│  db/store.go             ← 本地配置持久化（高级参数独立存储）  │
└──────────────────────────┬──────────────────────────────────┘
                            │  REST API
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Vue 前端（Vuetify）                      │
│                                                              │
│  /login              认证                                     │
│  /                   Dashboard（状态 + 流量图）                │
│  /inbounds           Inbound 管理                              │
│                      ├─ [基础] xboard inbound 骨架（只读/同步）│
│                      └─ [高级] 节点高级参数（增改）              │
│  /users              用户列表（只读）                         │
│  /rules              路由规则（域名/IP/协议/inbound_tag）       │
│  /users-rules        用户规则绑定                              │
│  /outbounds          出口节点（全协议）                       │
│  /dns                DNS 配置                                  │
│  /tls                TLS / ACME / Reality                    │
│  /services           附加服务（Warp/Tailscale/Naive/Tor/SSH）│
│  /endpoints          Endpoints                               │
│  /settings           节点设置                                  │
│  /logs               日志                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. xboard v2 协议（最小化，对用户透明）

### 3.1 鉴权

```
Token: HMAC-SHA256(secret, timestamp)
X-Token-Time: {unix_timestamp}
```

### 3.2 端点（最小化）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v2/server/handshake` | 注册，返回 Version |
| GET | `/api/v2/server/config` | 拉取 inbound 骨架（tag/port/type/basic settings） |
| GET | `/api/v2/server/users` | 拉取用户变更增量 |
| POST | `/api/v2/server/traffic` | 上报流量（**对用户透明**） |
| POST | `/api/v2/server/status` | 上报系统状态 |

### 3.3 数据流

```
xboard → inbound 骨架（tag/port/type/uuid/password）
    ↓
pupmsub 查本地高级配置（uTLS/reality/obfs/plugin/...）
    ↓
合并 → 完整 sing-box inbound
    ↓
生成 sing-box.json → Restart sing-box
```

---

## 4. Inbound 配置分层设计

### 4.1 inbound 结构

```json
{
  "tag": "节点-1",
  "type": "vless",
  "listen": "0.0.0.0",
  "listen_port": 443,

  // ---- xboard 下发（骨架，可选从 xboard 同步）----
  "xboard_tag": "xboard-inbound-1",    // 对应 xboard 的 inbound tag
  "uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "flow": "xtls-rprx-vision",

  // ---- 节点高级设置（本地存储，xboard 不懂）----
  "tls": {
    "enabled": true,
    "server_name": "example.com",

    // uTLS 指纹（xboard 不支持）
    "utls": {
      "enabled": true,
      "fingerprint": "chrome"
    },

    // Reality（xboard 不支持）
    "reality": {
      "enabled": true,
      "public_key": "xxxxxxxx",
      "short_id": "xxxxxxxx"
    }
  },

  // Shadowsocks 插件（xboard 不支持）
  "plugin": "v2ray-plugin",
  "plugin_opts": "tls;host=example.com",

  // Hysteria2 混淆（xboard 不支持）
  "obfs": {
    "enabled": true,
    "type": "salamander",
    "password": "xxxxxxxx"
  },

  // Mux 多路复用（xboard 不支持）
  "multiplex": {
    "enabled": true,
    "max_connections": 8
  }
}
```

### 4.2 高级参数清单（xboard 不支持的部分）

| 类别 | 参数 | 说明 |
|------|------|------|
| **uTLS** | `fingerprint` | chrome / firefox / safari / android / edge / 随机 |
| **Reality** | `public_key` / `short_id` / `server_name` | VLESS Reality 目标 |
| **Shadowsocks Plugin** | `plugin` / `plugin_opts` | v2ray-plugin / obfs-server |
| **Hysteria2 Obfs** | `obfs` type / password | salamander / http 混淆 |
| **VMess 增强** | `vmess_security` | aes-128-gcm / chacha20-poly1305 / 强制 |
| **VLESS Flow** | `flow` | xtls-rprx-vision / 6pl4in1 / 强制 |
| **Trojan-GO** | `transport` | tr websocket / tr http |
| **Mux** | `max_connections` / `max_streams` | 多路复用 |
| **TUN** | `stack` / `auto_route` / `mtu` | 透明代理 |
| **Trojan** | `fallback` | 多路 fallback |
| **TUIC** | `udp_relay_mode` / `congestion_control` | QUIC 拥塞控制 |

---

## 5. 前端视图

### 5.1 Inbounds `/inbounds`（核心视图）

**两个 Tab**：

**Tab 1 — 基础协议**（xboard inbound 骨架，可从 xboard 同步）

| 字段 | 说明 |
|------|------|
| tag | inbound 标签 |
| protocol | 协议类型（vmess/vless/trojan/ss/hysteria2/tuic/etc） |
| port | 监听端口 |
| listen | 监听地址 |
| uuid / password | 鉴权信息（从 xboard 同步或本地填写） |
| xboard inbound ID | 对应 xboard inbound（可选绑定） |

**Tab 2 — 高级设置**（节点本地，xboard 不懂的参数）

根据 protocol 类型动态展示对应的高级选项：

```
协议类型选择
    ↓
[ 基础协议 ]          [ 高级设置 ]
───────────────────────
● TLS & Reality
  ├─ Enable TLS: on/off
  ├─ SNI: example.com
  ├─ ALPN: [h2, http/1.1]
  ├─ uTLS Fingerprint: [chrome / firefox / safari / android / 随机]
  └─ Reality:
       ├─ Enable: on/off
       ├─ Public Key:
       └─ Short ID:

● Shadowsocks 插件
  ├─ Plugin: [v2ray-plugin / obfs-server / 无]
  └─ Plugin Options: tls;host=example.com

● Hysteria2 混淆
  ├─ Obfs Type: [salamander / http / 无]
  └─ Obfs Password:

● 多路复用
  ├─ Enable Mux: on/off
  └─ Max Connections: 8

● TUN 透明代理
  ├─ Stack: [system / gVisor / mixed]
  ├─ MTU: 9000
  ├─ Auto Route: on/off
  └─ Strict Route: on/off
```

### 5.2 其他视图（不变）

| 视图 | 说明 |
|------|------|
| Users `/users` | 只读（来自 xboard） |
| Rules `/rules` | 路由规则（域名/IP/协议/inbound_tag） |
| UsersRules `/users-rules` | 用户 → outbound 绑定 |
| Outbounds `/outbounds` | 出口节点 |
| Dns `/dns` | DNS 配置 |
| Tls `/tls` | TLS 全局证书（ACME/DNS providers） |
| Services `/services` | 附加服务 |
| Endpoints `/endpoints` | 规则集 |
| Settings `/settings` | 节点设置 |
| Logs `/logs` | 日志 |

---

## 6. 本地数据持久化

| 文件 | 内容 |
|------|------|
| `config.json` | pupmsub 自身配置（xboard 对接 + 路径） |
| `inbounds_basic.json` | inbound 骨架（tag/port/type/auth — xboard 同步 + 本地） |
| `inbounds_advanced.json` | 高级参数（uTLS/reality/obfs/plugin/mux — 本地独立存储） |
| `users_rules.json` | 用户 → outbound 绑定 |
| `rules.json` | 路由规则 |
| `outbounds.json` | 出口节点 |
| `dns.json` | DNS 配置 |
| `tls.json` | TLS 全局配置（ACME/providers） |
| `services.json` | 附加服务 |
| `endpoints.json` | Endpoints |
| `traffic_snap.json` | 流量快照 |

---

## 7. sing-box 配置生成（generator.go）

```
xboard GET /config → inbound 骨架
    ↓
合并本地 inbounds_advanced[]（按 tag 匹配）
    ↓
路由规则（rules[]）
出站节点（outbounds[]）
DNS 配置（dns[]）
TLS 证书（tls.json）
    ↓
sing-box.json
    ↓
singbox.go → Restart sing-box
```

---

## 8. API

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/auth/login` | 认证 |
| GET | `/api/status` | 节点状态 |
| GET | `/api/inbounds` | inbound 完整配置（基础 + 高级合并） |
| PUT | `/api/inbounds` | 更新 inbound |
| GET | `/api/inbounds/basic` | inbound 骨架（xboard 同步字段） |
| PUT | `/api/inbounds/basic` | 更新骨架 |
| GET | `/api/inbounds/advanced` | 高级参数（本地） |
| PUT | `/api/inbounds/advanced` | 更新高级参数 |
| GET | `/api/users` | 用户列表（只读） |
| GET/PUT | `/api/users-rules` | 用户规则绑定 |
| GET/PUT | `/api/rules` | 路由规则 |
| GET/PUT | `/api/outbounds` | 出口节点 |
| GET/PUT | `/api/dns` | DNS 配置 |
| GET/PUT | `/api/tls` | TLS 全局配置 |
| GET/PUT | `/api/services` | 附加服务 |
| GET/PUT | `/api/endpoints` | Endpoints |
| GET | `/api/config` | 完整 sing-box.json |
| PUT | `/api/config` | 更新 sing-box.json |
| GET/PUT | `/api/settings` | 节点设置 |
| GET | `/api/traffic` | 近 24h 流量（透明） |
| GET | `/api/logs` | 日志 |
| POST | `/api/xboard/sync` | 触发 xboard 同步 |
| POST | `/api/singbox/restart` | 重启 sing-box |

---

## 9. 目录结构

```
pupmsub/
├── main.go
├── go.mod
├── cmd/root.go / run.go / sync.go / restart.go / status.go / version.go
├── config/config.go
├── network/
│   ├── client.go       # xboard v2 HTTP + HMAC-SHA256 + ETag
│   └── types.go
├── service/
│   ├── daemon.go        # handshake / sync / report / status
│   ├── singbox.go       # 进程管理
│   ├── generator.go     # 骨架 + 高级参数 → sing-box.json
│   └── stats.go
├── db/store.go         # 分层存储（basic/advanced 分开）
├── logger/logger.go
├── api/
│   ├── server.go
│   ├── auth.go
│   ├── inbounds.go      # /inbounds（合并） /inbounds/basic /inbounds/advanced
│   ├── users.go / rules.go / users_rules.go
│   ├── outbounds.go / dns.go / tls.go / services.go / endpoints.go
│   ├── settings.go / config.go / traffic.go / logs.go / xboard.go / singbox.go
├── frontend/src/
│   ├── views/
│   │   ├── Inbounds.vue       # ★ 核心：两个 Tab（基础 + 高级）
│   │   ├── Users.vue           # 只读
│   │   ├── Rules.vue
│   │   ├── UsersRules.vue
│   │   ├── Outbounds.vue
│   │   ├── Dns.vue
│   │   ├── Tls.vue
│   │   ├── Services.vue
│   │   ├── Endpoints.vue
│   │   ├── Settings.vue
│   │   ├── Logs.vue
│   │   ├── Dashboard.vue
│   │   └── Login.vue
│   ├── components/
│   │   ├── InboundAdvanced.vue  # ★ 高级设置面板（uTLS/Reality/Obfs/Plugin/Mux/TUN）
│   │   ├── protocols/           # 参考 s-ui/protocols/ 重用
│   │   ├── tls/                # TLS 组件
│   │   ├── transports/         # 传输层组件
│   │   └── ...
│   └── locales/
└── web/web.go
```

---

## 10. 构建（GitHub Actions）

| 平台 | 架构 | 场景 |
|------|------|------|
| Linux | amd64 (musl) | Alpine |
| Linux | amd64 (glibc) | Debian/Ubuntu |
| Linux | arm64 | ARM VPS |
| Linux | armv7 | 树莓派 |

---

## 11. 架构原则

| 分层 | 来源 | 管理方 |
|------|------|-------|
| inbound 骨架（tag/port/type/uuid/password） | xboard 或本地 | 均可 |
| uTLS 指纹 / Reality / SS 插件 / Hysteria2 obfs / Mux | 本地 | pupmsub |
| 用户列表 | xboard | 只读 |
| 路由规则 / DNS / 出口节点 / TLS 证书 | 本地 | pupmsub |
| 流量上报 | pupmsub → xboard | 对用户透明 |
