#────────────────────────────── 选项解析 ──────────────────────────────
# 模块: 10-options.sh

BRIEF=0; NOCOLOR=0; REVEAL=0; SECTION="all"; OFFLINE=0; DEEP_GEO=0; RADIO=0; JSON=0

usage() {
cat <<EOF
region-trace-audit v$VERSION — 陆港澳用户环境痕迹检测器(只读)

用法: region-trace-audit.sh [选项]
  --brief            只实时输出 可疑/暴露 行(汇总仍完整)
  --no-color         禁用颜色(亦遵循 NO_COLOR 环境变量/非终端自动禁用)
  --reveal           显示完整 IP/邮箱(默认脱敏:IP 前两段、邮箱用户名掩码)
  --offline          跳过一切外联(出口/路由/DNS 探测转为跳过,本地项照常)
  --deep-geo         对 known_hosts 与活跃连接对端做 GeoIP(向 ip-api 发送待查 IP;
                     默认关闭,开启前请知悉)
  --json             机器可读输出(单 JSON 对象,替代人读报告;退出码不变)
  --section <cat>    只运行指定类别: sysinfo macos cloud boot kernelnet session
                                  egress path proxy dns wsl locale mirror fs anti
                                  services gui browser hw time usegeo
  --radio            启用无线/蜂窝检查(iw 监管域/WiFi 关联/WWAN MCC/GNSS;物理在场证据)
  -h, --help         本帮助

v0.5 新增:macOS 适配层(系统区域/系统代理/launchd/输入法/用户字体/Homebrew)、
--json 机器可读输出(单 JSON 对象:meta/summary/items/usegeo_view,退出码不变)。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --brief)    BRIEF=1 ;;
    --no-color) NOCOLOR=1 ;;
    --reveal)   REVEAL=1 ;;
    --offline)  OFFLINE=1 ;;
    --deep-geo) DEEP_GEO=1 ;;
    --radio)    RADIO=1 ;;
    --json)     JSON=1 ;;
    --section)  shift; SECTION="${1:-}"; [ -z "$SECTION" ] && SECTION="all" ;;
    -h|--help)  usage; exit 0 ;;
    *) printf '未知参数: %s(见 --help)\n' "$1" >&2; exit 64 ;;
  esac
  shift
done
