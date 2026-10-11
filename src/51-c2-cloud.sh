#────────────────────────────── C2 cloud ──────────────────────────────
# 模块: 51-c2-cloud.sh

check_c2() {
  hdr "C2 cloud · 中资云与定制系统(信息级)"

  _hits=""
  _vendor=""; _product=""

  # DMI/SMBIOS
  if [ -r /sys/class/dmi/id/sys_vendor ]; then
    _vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    _product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    if printf '%s' "$_vendor $_product" | grep -qE "$CN_CLOUD_DMI_RE"; then
      _hits="DMI[$_vendor/$_product]"
    elif printf '%s' "$_vendor" | grep -qiE '^HUAWEI$'; then
      _hits="DMI[$_vendor](华为硬件或华为云,需 product 区分)"
    fi
    [ -n "$_vendor" ] && report INFO cloud/dmi "DMI: $_vendor / ${_product:-?}"
  else
    report SKIP cloud/dmi "(Linux DMI 接口不适用或不可读;macOS 硬件见 hw 类)"
  fi

  # 云 agent 进程
  _ps=$(ps_filtered)
  if [ -n "$_ps" ]; then
    _ag=$(printf '%s' "$_ps" | grep -vE 'grep|region-trace' | grep -icE "$CLOUD_AGENT_PROC_RE" || true)
    if [ "${_ag:-0}" -gt 0 ]; then
      _hits="${_hits:+$_hits; }云agent进程 x$_ag(运行中)"
    fi
  else
    report SKIP cloud/agent-proc "(ps 不可用)"
  fi

  # 云 agent 目录
  for _d in $CLOUD_AGENT_DIRS; do
    [ -d "$_d" ] && _hits="${_hits:+$_hits; }目录 $_d"
  done

  # 云内网镜像源(C9 深查,此处判定归属)
  for _f in /etc/apt/sources.list /etc/yum.repos.d /etc/dnf/dnf.conf /etc/pacman.d/mirrorlist /etc/apk/repositories; do
    if [ -e "$_f" ]; then
      if grep -rE "$CLOUD_INT_MIRROR_RE" "$_f" >/dev/null 2>&1; then
        _hits="${_hits:+$_hits; }内网镜像源($_f)"
        break
      fi
    fi
  done

  # 定制痕迹
  for _f in /etc/motd /etc/issue; do
    if [ -r "$_f" ] && grep -qiE 'alibaba|tencent|huawei|volcano|aliyun' "$_f" 2>/dev/null; then
      _hits="${_hits:+$_hits; }$_f 含厂商定制字样"
    fi
  done

  # 预装包
  _pkgs=""
  if have rpm; then _pkgs=$(rpm -qa 2>/dev/null | grep -iE '^(aliyun|tencent|qcloud|huawei|volcano)' | head -n 8)
  elif have dpkg; then _pkgs=$(dpkg -l 2>/dev/null | awk '{print $2}' | grep -iE '^(aliyun|tencent|qcloud|huawei|volcano)' | head -n 8)
  fi
  [ -n "$_pkgs" ] && _hits="${_hits:+$_hits; }预装包: $(printf '%s' "$_pkgs" | tr '\n' ' ' | cut -c1-120)"

  if [ -n "$_hits" ]; then
    report INFO cloud/summary "检出中资云特征: $_hits(节点国内/海外待 egress 类判定;监控 agent 意味着数据回传中资厂商)"
  else
    report CLEAN cloud/summary "未检出中资云/定制系统特征(普通 IDC 不作检测点)"
  fi
}
