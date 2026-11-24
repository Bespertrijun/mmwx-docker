# syntax=docker/dockerfile:1
# ============================================================
# 妙妙屋X 开心版 面板 Docker 镜像
# 二进制为静态链接的 Go 程序，基于 Alpine 即可运行
# ============================================================
FROM alpine:3.21

# 构建参数（docker build --build-arg 覆盖）：
#   MMWX_TAG   面板 release 的 tag，默认当前最新 mmwx-v0.6.3
#   MMWX_REPO  二进制来源仓库
#   GH_PROXY   GitHub 加速前缀（国内网络用），如 https://ghfast.top/
ARG MMWX_TAG=mmwx-v0.6.3
ARG MMWX_REPO=zako-li/miaomiaowux
ARG GH_PROXY=""
# 由 BuildKit 自动注入：amd64 / arm64
ARG TARGETARCH=amd64

RUN apk add --no-cache ca-certificates tzdata curl \
    && case "$TARGETARCH" in \
         amd64|arm64) ARCH="$TARGETARCH" ;; \
         *) echo "不支持的架构: $TARGETARCH（只有 amd64 / arm64）" >&2; exit 1 ;; \
       esac \
    && url="${GH_PROXY:+${GH_PROXY%/}/}https://github.com/${MMWX_REPO}/releases/download/${MMWX_TAG}/mmwx-linux-${ARCH}" \
    && echo "下载: $url" \
    && curl -fSL --connect-timeout 20 --retry 3 -o /usr/local/bin/mmwx "$url" \
    && chmod 0755 /usr/local/bin/mmwx \
    && apk del curl \
    && mkdir -p /etc/mmwx/data/agent-bin

# 面板环境变量（与官方 systemd 配置一致）：
#   PORT                     监听端口，默认 12889
#   MMWX_DATA_DIR            数据目录（SQLite 等），默认 /etc/mmwx/data
#   MMWX_GH_PROXY            GitHub 加速前缀（自更新 / 下发 Agent 用）
#   MMWX_GH_TOKEN            GitHub token，提高 API 限额
#   MMWX_UPDATE_REPO         设 off 关闭面板在线更新（容器内建议关闭，见 README）
#   MMWX_AGENT_GITHUB_REPO   Agent 下载来源仓库，设 off 关闭
#   MMWX_AGENT_DOWNLOAD_BASE 自建 Agent 镜像源
ENV PORT=12889 \
    MMWX_DATA_DIR=/etc/mmwx/data \
    TZ=Asia/Shanghai

VOLUME ["/etc/mmwx/data"]
EXPOSE 12889

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/login" || exit 1

CMD ["/usr/local/bin/mmwx"]
