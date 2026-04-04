# pupmsub

基于 [V2bX](https://github.com/InazumaV/V2bX) 的 V2board 节点服务端 fork，定制化适配 [Pupm](https://pupm.us) 自用需求。

**依赖 V2board >= 1.7.0**

## 支持的协议

| 协议 | 状态 | 说明 |
|---|---|---|
| VLESS + REALITY | ✅ | XTLS + xtls-rprx-vision |
| VMess | ✅ | |
| Trojan | ✅ | |
| Shadowsocks | ✅ | AEAD / 2022-blake3 |
| Hysteria | ✅ | |
| TUIC | ✅ | |

## 安装

### 一键安装

```bash
wget -N https://raw.githubusercontent.com/pupmme/pupmsub/v2bx-script/script/install.sh && bash install.sh
```

### 手动构建

```bash
git clone https://github.com/pupmme/pupmsub.git
cd pupmsub
go build -ldflags '-s -w' -tags "xray sing" -o V2bX .
```

## 配置文件

参考 `script/config/` 目录下的模板，主要包含：

- `config.yml` — 主配置（API 地址、节点信息、日志级别）
- `node.yml` — 节点协议与出站路由配置
- `dns.json` — DNS 解析规则
- `route.json` — 流量路由规则
- `custom_inbound.json` — 入站附加配置（可选）
- `custom_outbound.json` — 出站附加配置（可选）

详细配置文档：[V2bX 使用教程](https://yuzuki-1.gitbook.io/v2bx-doc/)

## 监控

内置 Prometheus 埋点，接入方式：

1. 在 `config.yml` 中开启 debug HTTP 服务（默认监听 `:10092`）

2. 添加 Prometheus scrape target：

```yaml
scrape_configs:
  - job_name: 'pupmsub'
    static_configs:
      - targets: ['localhost:10092']
    metrics_path: '/metrics'
    scrape_interval: 30s
```

3. 可用指标（prefix `v2bx_`）：

| 指标 | 类型 | 说明 |
|---|---|---|
| `online_users` | gauge | 节点在线用户数 |
| `traffic_up_bytes` | counter | 累计上传流量 |
| `traffic_down_bytes` | counter | 累计下载流量 |
| `traffic_total_bytes` | gauge | 当前总流量 |
| `connections_active` | gauge | 活跃连接数 |

## 引用仓库

- [InazumaV/V2bX](https://github.com/InazumaV/V2bX) — 核心框架
- [SagerNet/sing-box](https://github.com/SagerNet/sing-box) — sing-box 内核
- [XTLS/Xray-core](https://github.com/XTLS/Xray-core) — Xray 内核
- [MKasumi/sing-box-shadow-tls](https://github.com/MKasumi/sing-box-shadow-tls) — ShadowTLS 协议
- [SagerNet/sing-shadowsocks](https://github.com/SagerNet/sing-shadowsocks) — Shadowsocks 实现

## 许可证

[Mozilla Public License 2.0](./LICENSE)
