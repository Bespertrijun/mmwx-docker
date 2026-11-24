# 妙妙屋X 开心版 —— Docker 自动同步方案

上游 [zako-li/miaomiaowux](https://github.com/zako-li/miaomiaowux) 一发新版，
本仓库的 Actions 自动构建多架构镜像推到 GHCR，服务器上的 Watchtower
自动拉取并重启容器。全链路无人值守。

```
上游 Release ──巡检──> GitHub Actions ──构建──> ghcr.io/bespertrijun/mmwx:latest
                                                      │
服务器 Watchtower ──每小时轮询──┘   （有新镜像 → 拉取 → 平滑重启 mmwx）
```

二进制是静态链接的 Go 程序（已实测 v0.6.3 启动正常、`/login` 返回 200），
镜像基于 Alpine，无 systemd 依赖。

## 服务器部署

镜像已公开，直接拉取即可：

```bash
mkdir mmwx && cd mmwx
curl -fsSL -o docker-compose.yml \
  https://raw.githubusercontent.com/Bespertrijun/mmwx-docker/main/docker-compose.yml
docker compose up -d
```

之后上游更新 → 最多 6 小时出镜像 → 最多再 1 小时服务器自动换新版。

## ‼️ 访问前必读（官方同样的坑）

面板前端依赖浏览器 WebCrypto，**只在 HTTPS 或 localhost 下可用**。
直接开 `http://服务器IP:12889/login` 会「全新安装却显示登录页、登不进去」。

二选一：

1. **SSH 隧道（最快）**：本机终端执行
   `ssh -L 12889:127.0.0.1:12889 root@服务器IP`，
   浏览器开 `http://127.0.0.1:12889/login`。
2. **域名 + 反代 HTTPS**：Caddy / Nginx 反代到 `127.0.0.1:12889`，
   访问 `https://你的域名/login`。

另外：地址**一定要带 `/login`**（根路径 `/` 是探针伪装页，显示
「探针暂时无法访问」属正常）；第一次打开是「创建管理员账号」，
首个注册用户自动成为管理员。

## 数据库（PostgreSQL）

compose 已默认带一个 `postgres:16-alpine` 容器，面板通过环境变量直连
（`MMWX_DATABASE_DRIVER=postgres` 等，官方二进制原生支持，已实测启动自动建表
82 张）。数据库端口**不对外暴露**，只在 compose 内网通信；密码已生成随机值，
要改的话 mmwx 和 postgres 两处同步改。

- 数据持久化：直接存在 compose 文件旁边的本地目录——业务数据在 `./pgdata`，
  面板附件（证书、订阅文件等）在 `./data`，备份整个目录即可。
  （`./pgdata` 里的文件属主是容器内 postgres 用户，属正常现象，别手动改权限。）
- 连接外部已有的 PostgreSQL：删掉 `postgres` 服务和 `depends_on`，把
  `MMWX_DATABASE_HOST` 等指向你的实例即可；远程连接按需把
  `MMWX_DATABASE_SSLMODE` 改成 `require`。
- **已有 SQLite 数据的旧安装**：面板内置 SQLite → PostgreSQL 迁移校验逻辑，
  但切换前务必先备份 `./data` 目录（里面有 `database.json` 和 sqlite 文件），
  建议先在测试环境验证再动生产。

## 常用操作

```bash
# 手动立刻检查上游有没有新版（不等定时）
# → GitHub 仓库 Actions 页点 Run workflow 即可

# 服务器上手动更新（不等 Watchtower）
docker compose pull mmwx && docker compose up -d mmwx

# 看日志
docker logs -f mmwx
docker logs -f watchtower
```

数据在本地目录 `./pgdata`（PostgreSQL）和 `./data`（面板附件）里，
换镜像、重建容器都不丢，备份直接拷目录。
回滚版本：`docker compose.yml` 里把 `latest` 换成具体 tag（如 `mmwx-v0.6.3`），
再 `docker compose up -d`。

## 工作原理说明

- **巡检**：Actions 每 6 小时查上游 Releases，取第一个匹配
  `mmwx` / `mmwx-v*` 的 tag（与官方安装脚本同一套规则，不会误中
  `mmwx-agent-*`），和仓库里的 `UPSTREAM_VERSION` 文件对比，变了才构建。
- **构建**：Buildx 一次出 `linux/amd64` + `linux/arm64` 两个架构，
  打上 `latest` 和上游 tag 两个标签推到 GHCR，然后 bot 把新版本号
  提交回 `UPSTREAM_VERSION`。
- **更新**：Watchtower 只监控带 `watchtower.enable=true` 标签的 mmwx
  容器，发现 `latest` 镜像有更新就拉取并平滑重启，`--cleanup` 顺手清掉旧镜像。
- 面板自带的在线更新已用 `MMWX_UPDATE_REPO=off` 关掉——容器里换二进制
  没有意义，升级统一走「换镜像」这条路，可回滚、可追溯。

## 环境变量（面板）

| 变量 | 作用 | 默认 |
| --- | --- | --- |
| `PORT` | 监听端口 | `12889` |
| `MMWX_DATA_DIR` | 数据目录（附件、证书等） | `/etc/mmwx/data` |
| `MMWX_DATABASE_DRIVER` | 数据库类型：`postgres` / `sqlite` | compose 已设 `postgres` |
| `MMWX_DATABASE_HOST` 等 | PG 地址/端口/库名/用户/密码 | 见 compose |
| `MMWX_DATABASE_SSLMODE` | PG TLS 模式，内网用 `disable` | `disable` |
| `MMWX_GH_PROXY` | GitHub 加速前缀（结尾带 `/`） | 空 |
| `MMWX_GH_TOKEN` | GitHub token，提高 API 限额 | 空 |
| `MMWX_UPDATE_REPO` | 面板在线更新，容器里建议 `off` | compose 已设 `off` |
| `MMWX_AGENT_GITHUB_REPO` | Agent 下载来源，`off` 关闭 | compose 已设 `off` |
| `MMWX_AGENT_DOWNLOAD_BASE` | 自建 Agent 镜像源 | 空 |

## 文件清单

| 文件 | 作用 |
| --- | --- |
| `Dockerfile` | 镜像构建（Alpine + 静态二进制，含健康检查） |
| `.github/workflows/auto-build.yml` | 定时巡检上游 + 自动构建推送 GHCR |
| `docker-compose.yml` | 服务器端：mmwx + Watchtower 自动更新 |
| `UPSTREAM_VERSION` | 记录上次构建的上游 tag（Actions 自动维护） |
