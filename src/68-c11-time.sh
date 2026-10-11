#────────────────────────────── C11 time ──────────────────────────────
# 模块: 68-c11-time.sh
# 定位:时间行为统计 → 作息时区推断(防 AI 后台污染:只取用户主动动作,簇化降噪)
# 红线:只采集小时分桶,不采集/不输出任何内容、命令文本、主机名

check_c11() {
  hdr "C11 time · 时间行为统计与作息时区推断"

  # 当前系统 UTC 偏移分钟数(本地时间源换算用;历史条目按当前时区回溯 —— 已知局限)
  _z=$(date +%z 2>/dev/null)
  OFFMIN=0
  case "$_z" in
    [+-][0-9][0-9][0-9][0-9])
      _sgn=${_z%????}; _hm=${_z#?}
      _hh=${_hm%??}; _mm=${_hm#??}
      case "$_hh" in 0?) _hh=${_hh#0} ;; esac
      case "$_mm" in 0?) _mm=${_mm#0} ;; esac
      OFFMIN=$((_hh*60+_mm))
      [ "$_sgn" = "-" ] && OFFMIN=$((-OFFMIN)) ;;
  esac

  _ev=""          # 全部事件 epoch(UTC)
  _src_n=""       # 各源计数说明

  # ── t1 登录时刻(wtmp,last -F;本地时间) ──
  _n1=0
  # 注:macOS last 无 -F(完整日期)选项,跳过 t1(zsh history/AI 会话已覆盖)
  if have last && last -F -n 400 >/dev/null 2>&1 && last -F -n 400 2>/dev/null | grep -q '^[a-zA-Z0-9]'; then
    _e1=$(last -F -n 400 2>/dev/null | awk -v off=$OFFMIN '
      function mke(y,mo,d,h,mi,s, era,yoe,doy,doe,days) {
        if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
        doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
        days=era*146097+doe-719468
        return days*86400+h*3600+mi*60+s-off*60
      }
      BEGIN{split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec",MN," ")
            for(i=1;i<=12;i++)M[MN[i]]=i}
      /^(reboot|shutdown|wtmp|btmp)/ {next}
      {
        for(f=3;f<=6;f++) if ($f ~ /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)$/) break
        if (f>6) next
        # $f=WD $(f+1)=Mon $(f+2)=Day $(f+3)=HH:MM:SS $(f+4)=Year
        if ($(f+3) !~ /^[0-9]{1,2}:[0-9][0-9]:[0-9][0-9]$/) next
        if ($(f+4) !~ /^[0-9][0-9][0-9][0-9]$/) next
        if (M[$(f+1)]=="") next
        split($(f+3),T,":")
        print mke($(f+4)+0, M[$(f+1)], $(f+2)+0, T[1]+0, T[2]+0, T[3]+0)
      }')
    _n1=$(printf '%s\n' "$_e1" | grep -c '^[0-9]' || true)
    [ "${_n1:-0}" -gt 0 ] && _ev="$_ev
$_e1"
  fi
  if [ "${_n1:-0}" -gt 0 ]; then _src_n="$_src_n 登录=$_n1"; else _src_n="$_src_n 登录=0"; fi

  # ── t2 shell history 时间戳(bash #epoch / zsh :epoch:;)(天然人工) ──
  _n2=0
  _h2="$HOME/.bash_history"
  if [ -r "$_h2" ]; then
    _n2=$(grep -c '^#[0-9]\{9,\}$' "$_h2" 2>/dev/null || true)
    if [ "${_n2:-0}" -gt 0 ]; then
      _ev="$_ev
$(grep '^#[0-9]\{9,\}$' "$_h2" | tr -d '#')"
    fi
  fi
  _h2z="$HOME/.zsh_history"
  if [ -r "$_h2z" ]; then
    _nz=$(sed -n 's/^: \([0-9]\{9,\}\):.*/\1/p' "$_h2z" 2>/dev/null | grep -c . || true)
    if [ "${_nz:-0}" -gt 0 ]; then
      _n2=$((_n2+_nz))
      _ev="$_ev
$(sed -n 's/^: \([0-9]\{9,\}\):.*/\1/p' "$_h2z")"
    fi
  fi
  _src_n="$_src_n history=$_n2"

  # ── t3 AI 会话用户输入时刻(claude/pi/codex;UTC ISO 时间戳;滤 tool_result/元数据) ──
  _n3=0
  for _base in "$HOME/.claude/projects" "$HOME/.pi/agent/sessions" "$HOME/.codex/sessions"; do
    [ -d "$_base" ] || continue
    _files=$(find "$_base" -name '*.jsonl' -mtime -120 2>/dev/null | head -n 150)
    [ -z "$_files" ] && continue
    _e3=$(printf '%s\n' "$_files" | LC_ALL=C xargs -r awk '
      function mke(y,mo,d,h,mi,s, era,yoe,doy,doe,days) {
        if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
        doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
        days=era*146097+doe-719468
        return days*86400+h*3600+mi*60+s
      }
      {
        if ($0 !~ /"role":"user"/ && $0 !~ /"type":"user"/) next
        if ($0 ~ /"tool_result"/ || $0 ~ /"function_call_output"/ || \
            $0 ~ /"toolUseResult"/ || $0 ~ /"isMeta":true/ || $0 ~ /"isSidechain":true/) next
        if (!match($0, /"timestamp":"[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) next
        ts=substr($0, RSTART+13, RLENGTH-13)
        split(ts, a, /[-T:]/)
        print mke(a[1]+0, a[2]+0, a[3]+0, a[4]+0, a[5]+0, a[6]+0)
      }' 2>/dev/null)
    _c=$(printf '%s\n' "$_e3" | grep -c '^[0-9]' || true)
    if [ "${_c:-0}" -gt 0 ]; then _n3=$((_n3+_c)); _ev="$_ev
$_e3"; fi
  done
  _src_n="$_src_n AI用户输入=$_n3"

  # ── t5 交互文件 mtime(Downloads/Documents/Desktop/常用 dotfile;120 天内) ──
  _n5=0
  _e5=""
  for _d in "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop"; do
    [ -d "$_d" ] || continue
    _e5="$_e5
$(find "$_d" -maxdepth 2 -type f -mtime -120 2>/dev/null | head -n 200 | xargs -r stat -c '%Y' 2>/dev/null)"
  done
  for _f in "$HOME/.bashrc" "$HOME/.gitconfig" "$HOME/.ssh/config" "$HOME/.config/tmux/tmux.conf"; do
    [ -f "$_f" ] && [ -n "$(find "$_f" -mtime -120 2>/dev/null)" ] && _e5="$_e5
$(stat -c '%Y' "$_f" 2>/dev/null)"
  done
  _n5=$(printf '%s\n' "$_e5" | grep -c '^[0-9]' || true)
  [ "${_n5:-0}" -gt 0 ] && _ev="$_ev
$_e5"
  _src_n="$_src_n 文件mtime=$_n5"

  # ── t7 git commit 时刻+作者时区偏移(最多 6 个仓库,500 条/仓) ──
  _n7=0; _tz7=""
  if have git; then
    _mymail=$(git config --global user.email 2>/dev/null)
    _repos=$(find "$HOME" -maxdepth 3 -name .git -type d 2>/dev/null | head -n 6)
    for _r in $_repos; do
      _d=${_r%/.git}
      if [ -n "$_mymail" ]; then
        _gl=$(git -C "$_d" log --all --author="$_mymail" --pretty='%ad' --date=iso -n 500 2>/dev/null)
      else
        _gl=$(git -C "$_d" log --all --pretty='%ad' --date=iso -n 500 2>/dev/null)
      fi
      [ -z "$_gl" ] && continue
      _tz7="$_tz7
$(printf '%s\n' "$_gl" | grep -oE '[+-][0-9]{4}$' | sort | uniq -c)"
      _e7=$(printf '%s\n' "$_gl" | awk -v off=0 '
        function mke(y,mo,d,h,mi,s,om, era,yoe,doy,doe,days) {
          if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
          doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
          days=era*146097+doe-719468
          return days*86400+h*3600+mi*60+s-om*60
        }
        {
          if (split($0, a, /[-: ]/) < 6) next
          om = (a[7] ~ /^[+-]/) ? (substr(a[7],2,2)*60+substr(a[7],4,2)) * (a[7]~/^-/?-1:1) : 0
          print mke(a[1]+0, a[2]+0, a[3]+0, a[4]+0, a[5]+0, a[6]+0, om)
        }')
      _c=$(printf '%s\n' "$_e7" | grep -c '^[0-9]' || true)
      [ "${_c:-0}" -gt 0 ] && { _n7=$((_n7+_c)); _ev="$_ev
$_e7"; }
    done
  fi
  _src_n="$_src_n git提交=$_n7"

  # ── t9 包安装时刻(dnf/apt/pacman;本地时间) ──
  _n9=0; _e9=""
  if have dnf; then
    _e9=$(dnf history list --reverse 2>/dev/null | awk -v off=$OFFMIN -F'|' '
      function mke(y,mo,d,h,mi,s,om, era,yoe,doy,doe,days) {
        if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
        doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
        days=era*146097+doe-719468
        return days*86400+h*3600+mi*60+s-om*60
      }
      $1 ~ /^[ ]*[0-9]+[ ]*$/ && $4 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
        gsub(/^ +| +$/,"",$4); split($4, p, /[ :-]/)
        print mke(p[1]+0,p[2]+0,p[3]+0,p[4]+0,p[5]+0,0, off)
      }')
  elif [ -r /var/log/apt/history.log ]; then
    _e9=$(sed -n 's/^Start-Date: \([0-9-]\{10\}\)  \([0-9:]\{8\}\).*/\1 \2/p' /var/log/apt/history.log | awk -v off=$OFFMIN '
      function mke(y,mo,d,h,mi,s,om, era,yoe,doy,doe,days) {
        if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
        doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
        days=era*146097+doe-719468
        return days*86400+h*3600+mi*60+s-om*60
      }{ split($1,a,"-"); split($2,b,":"); print mke(a[1]+0,a[2]+0,a[3]+0,b[1]+0,b[2]+0,b[3]+0, off) }')
  fi
  _n9=$(printf '%s\n' "$_e9" | grep -c '^[0-9]' || true)
  [ "${_n9:-0}" -gt 0 ] && _ev="$_ev
$_e9"
  _src_n="$_src_n 装包=$_n9"

  # ── t10 桌面交互旁证(输入法词库/浏览器历史文件 mtime,存在才计) ──
  _n10=0; _e10=""
  for _f in "$HOME/.config/fcitx/profile" "$HOME/.local/share/fcitx5" "$HOME/.config/ibus"; do
    if [ -e "$_f" ]; then
      _e10="$_e10
$(find "$_f" -type f -mtime -120 2>/dev/null | head -n 30 | xargs -r stat -c '%Y' 2>/dev/null)"
    fi
  done
  for _f in "$HOME/.config/google-chrome/Default/History" "$HOME/.mozilla/firefox"/*/"places.sqlite"; do
    [ -f "$_f" ] && _e10="$_e10
$(stat -c '%Y' "$_f" 2>/dev/null)"
  done
  _n10=$(printf '%s\n' "$_e10" | grep -c '^[0-9]' || true)
  [ "${_n10:-0}" -gt 0 ] && _ev="$_ev
$_e10"
  _src_n="$_src_n 桌面旁证=$_n10"

  # ── t6 重启时刻(仅 INFO,不入扫描) ──
  if have last && last -F reboot -n 10 2>/dev/null | grep -q 'reboot'; then
    _rb=$(last -F reboot -n 10 2>/dev/null | grep -c 'reboot' || true)
    report INFO time/reboots "近 $_rb 次重启(wtmp;云主机重启多由控制台/宿主发起,不作作息依据)"
  fi

  # ── t4 聚合:排序去重 → 5 分钟簇化取簇首(人簇发,AI 平铺;降权爆发) ──
  _n_raw=$(printf '%s\n' "$_ev" | grep -c '^[0-9]' || true)
  if [ "${_n_raw:-0}" -lt 30 ]; then
    report SKIP time/infer "(有效事件 ${_n_raw:-0} 个 <30,样本不足,不推断;${_src_n# })"
    return
  fi
  _cl=$(printf '%s\n' "$_ev" | grep '^[0-9]' | sort -n | uniq | awk '
    { if ($1 - prev > 300 || NR==1) { print $1; prev = $1 } }')
  _ncl=$(printf '%s\n' "$_cl" | grep -c '^[0-9]' || true)

  # ── UTC 直方图 + offset 扫描(-12…+14,步长 0.5h;得分 = P(08–24 本地) − P(01–07 本地)) ──
  _res=$(printf '%s\n' "$_cl" | awk '
    { h[int($1/3600)%24]++; wd[int(($1/86400+4))%7]++ }
    END {
      n=0; for(i=0;i<24;i++) n+=h[i]
      best_s=-2
      for (oi=-24; oi<=28; oi++) {
        off=oi*0.5; act=0; slp=0
        for (i=0;i<24;i++) {
          lh=i+off; while (lh<0) lh+=24; lh=lh%24
          if (lh>=8 && lh<24) act+=h[i]
          else if (lh>=1 && lh<7) slp+=h[i]
        }
        S[oi]=(act-slp)/n
        if (S[oi]>best_s) best_s=S[oi]
      }
      offs=""; first=1; sec_s=-2
      for (oi=-24; oi<=28; oi++) {
        if (S[oi] >= best_s-0.005) {
          if (first) { offs=sprintf("%.1f", oi*0.5); first=0 }
          else offs=offs "," sprintf("%.1f", oi*0.5)
        } else if (S[oi] > sec_s) sec_s=S[oi]
      }
      we=0; for(i=0;i<7;i++) if (i==0||i==6) we+=wd[i]
      printf "%s %.3f %.3f %.3f\n", offs, best_s, sec_s, (n?we/n:0)
      m=0; for(i=0;i<24;i++) if (h[i]>m) m=h[i]
      for(i=0;i<24;i++) printf "%02d %d\n", i, (m? int(h[i]*30/m+0.5) : 0)
    }')
  _offs=$(printf '%s\n' "$_res" | sed -n '1p' | awk '{print $1}')
  _bo=${_offs%%,*}
  _bs=$(printf '%s\n' "$_res" | sed -n '1p' | awk '{print $2}')
  _b2=$(printf '%s\n' "$_res" | sed -n '1p' | awk '{print $3}')
  _we=$(printf '%s\n' "$_res" | sed -n '1p' | awk '{print $4}')

  case "$_bs" in
    0.*|1.*) : ;;
    *) _bs=0 ;;
  esac
  if awk "BEGIN{exit !($_bs >= 0.55)}"; then _conf=高
  elif awk "BEGIN{exit !($_bs >= 0.35)}"; then _conf=中
  else _conf=低; fi

  # ASCII 直方图(UTC 小时分布;--brief/--json 时省略,判定行仍输出)
  if [ "$BRIEF" != 1 ] && [ "${JSON:-0}" != 1 ]; then
    printf '%s   UTC 小时分布(30 格满幅,簇首 %d 个/原始 %d 个;%s)%s\n' "$C_DIM" "$_ncl" "$_n_raw" "$(printf '%s' "$_src_n" | sed 's/^ //')" "$C_RST"
    printf '%s\n' "$_res" | tail -n 24 | awk -v c="$C_DIM" -v r="$C_RST" \
      '{printf "%s   %s %s%s\n", c, $1, substr("────────────────────────────", 1, $2), r}'
  fi

  # ── 判定 1:作息推断 vs 系统时区设置(一致性检验) ──
  TZ_INFER_OFF=$_offs; TZ_INFER_CONF=$_conf; TZ_INFER_N=$_ncl
  _olo=99; _ohi=-99
  for _o in $(printf '%s' "$_offs" | tr ',' ' '); do
    awk "BEGIN{exit !($_o < $_olo)}" && _olo=$_o
    awk "BEGIN{exit !($_o > $_ohi)}" && _ohi=$_o
  done
  # 东八关联度三档:contains(区间含 8.0,强)/ near(东亚工作节奏段 5–8.5,上缘≥7;
  # +7 时区如曼谷/雅加达/河内/珀斯亦可解释,仅作中等关联)/ none(无关联)
  _e8rel=none
  awk "BEGIN{exit !($_olo <= 8.0 && 8.0 <= $_ohi)}" && _e8rel=contains
  [ "$_e8rel" = none ] && awk "BEGIN{exit !($_ohi >= 7.0 && $_ohi <= 8.5 && $_olo >= 5.0)}" && _e8rel=near
  TZ_INFER_E8=no; [ "$_e8rel" != none ] && TZ_INFER_E8=yes
  case "$_e8rel" in
    contains) _e8desc="作息区间含 UTC+8" ;;
    near)     _e8desc="东/东南亚工作节奏段(UTC+${_olo}–${_ohi};+7 时区如曼谷/雅加达/珀斯亦可解释)" ;;
    *)        _e8desc="" ;;
  esac
  report INFO time/infer "作息推断 UTC+${_offs}(置信${_conf};最佳得分 $_bs,次优 $_b2;周末占比 $(awk "BEGIN{printf \"%.0f%%\", $_we*100}"))${_e8desc:+ · $_e8desc}"
  _tz_hit=""; case "${TZ_CLASS:-}" in CN|HKMO) _tz_hit=hit ;; esac
  if [ -z "${TZ_NAME:-}" ]; then
    report SKIP time/tz-consist "(系统时区不可探测,无法与作息比对)"
  elif [ "$_conf" = "低" ]; then
    report INFO time/tz-consist "作息推断置信低(直方图平坦/混合用户/自动化占比高),关联性弱,不作一致性判定(系统时区 $TZ_NAME)"
  else
    _so=$(tz_off_hours "$TZ_NAME")
    if [ -n "$_so" ] && awk "BEGIN{exit !($_so >= $_olo && $_so <= $_ohi)}"; then
      report CLEAN time/tz-consist "作息区间 UTC+${_olo}–${_ohi} 覆盖系统时区偏移(UTC+${_so})—— 时区设置与实际使用节奏一致(佐证)"
    elif [ -n "$_so" ]; then
      if awk "BEGIN{exit !($_so < $_olo)}"; then _d=$(awk "BEGIN{printf \"%.1f\", $_olo-$_so}"); else _d=$(awk "BEGIN{printf \"%.1f\", $_so-$_ohi}"); fi
      if awk "BEGIN{exit !($_d >= 1.0)}"; then
        if [ "$_e8rel" != none ]; then
          report SUSPICIOUS time/tz-consist "作息推断 UTC+${_offs}(置信${_conf},${_e8desc})与系统时区 $TZ_NAME(UTC+${_so})偏差 ${_d}h —— 时区设置与实际使用节奏不一致(作息软证据,长居东八者特征)"
        elif [ "$_tz_hit" = hit ]; then
          report SUSPICIOUS time/tz-consist "系统时区为陆港澳($TZ_NAME,UTC+${_so})而作息推断 UTC+${_offs}(偏差 ${_d}h)—— 时区声明与使用节奏矛盾(伪装痕迹或样本污染)"
        else
          report SUSPICIOUS time/tz-consist "作息推断 UTC+${_offs}(置信${_conf})与系统时区 $TZ_NAME(UTC+${_so})偏差 ${_d}h —— 时区设置与实际使用节奏不一致"
        fi
      else
        report INFO time/tz-consist "作息区间 UTC+${_olo}–${_ohi} 与系统时区(UTC+${_so})偏差 ${_d}h(轻微;夜猫型作息会前移推断值)"
      fi
    else
      report SKIP time/tz-consist "(系统时区偏移不可解析: $TZ_NAME)"
    fi
  fi

  # ── 判定 2:内地法定假日/调休补班日历检验(调休为内地特有;港澳及海外无此实践) ──
  _off8=$(printf '%s' "$_offs" | tr ',' '\n' | awk '{d=($1>8?$1-8:8-$1); if(NR==1||d<bd){bd=d;bo=$1}} END{print bo}')
  _cal=$(printf '%s\n' "$_cl" | awk -v off="$_off8" -v hol="$CN_HOLIDAYS" -v mk="$CN_MAKEUP" '
    function dfc(y,mo,d, era,yoe,doy,doe) {
      if (mo<=2){y--}; era=int((y>=0?y:y-399)/400); yoe=y-era*400
      doy=int((153*(mo-3)+2)/5)+d-1; doe=yoe*365+int(yoe/4)-int(yoe/100)+doy
      return era*146097+doe-719468
    }
    function cfd(z, era,doe,yoe,y,doy,mp,dd) {
      z+=719468; era=int((z>=0?z:z-146096)/146097); doe=z-era*146097
      yoe=int((doe-int(doe/1460)+int(doe/36524)-int(doe/146096))/365)
      y=yoe+era*400; doy=doe-(365*yoe+int(yoe/4)-int(yoe/100))
      mp=int((5*doy+2)/153); dd=doy-int((153*mp+2)/5)+1
      mp+=3; if (mp>12){mp-=12;y++}
      return sprintf("%04d%02d%02d", y, mp, dd)
    }
    BEGIN {
      nh=split(hol,H," "); for(i=1;i<=nh;i++) HOL[H[i]]=1
      nm=split(mk,M," "); for(i=1;i<=nm;i++) MK[M[i]]=1
    }
    {
      lt=$1+off*3600; days=int(lt/86400); dt=cfd(days); dow=(days+4)%7
      if (MK[dt]) { mkev++; if(!(dt in MKD)){MKD[dt]=1; mkd++} }
      else if (HOL[dt] && dow!=0 && dow!=6) { hev++; if(!(dt in HD)){HD[dt]=1; hd++} }
      else if (dow==0||dow==6) { wev++ }
      else { wdev++ }
      if (mn==""||$1<mn) mn=$1; if ($1>mx) mx=$1
    }
    END {
      if (mn!="") {
        dmin=cfd(int((mn+off*3600)/86400)); dmax=cfd(int((mx+off*3600)/86400))
        for (d in MK) if (d>=dmin && d<=dmax) mkcov++
        for (d in HOL) if (d>=dmin && d<=dmax) {
          dow2=(dfc(substr(d,1,4)+0, substr(d,5,2)+0, substr(d,7,2)+0)+4)%7
          if (dow2!=0 && dow2!=6) holcov++
        }
      }
      printf "%d %d %d %d %d %d %d %d\n", mkev+0, mkd+0, hev+0, hd+0, wdev+0, wev+0, mkcov+0, holcov+0
    }')
  set -- $_cal
  _mkev=$1; _mkd=$2; _hev=$3; _hd=$4; _wdev=$5; _wev=$6; _mkcov=$7; _holcov=$8
  if [ "${_mkcov:-0}" -eq 0 ] || [ "${_holcov:-0}" -lt 3 ]; then
    report SKIP time/cn-calendar "(数据窗口未覆盖足够调休/法定假日(补班日覆盖 ${_mkcov:-0} 个/假日工作日 ${_holcov:-0} 天;日历表覆盖 2024–2026),无法检验内地日历)"
  elif [ "${_mkev:-0}" -ge 1 ] && [ "${_hev:-0}" -eq 0 ]; then
    _cald="调休补班日活跃(${_mkd} 天/窗口内 ${_mkcov} 个)且法定假日(工作日 ${_holcov} 天)零活动 —— 作息遵循内地工作日历"
    if [ "$_tz_hit" = hit ]; then
      report INFO time/cn-calendar "$_cald(与系统时区一致,佐证)"
    elif [ "$_mkd" -ge 2 ]; then
      report SUSPICIOUS time/cn-calendar "$_cald(强烈作息软证据:调休为内地特有,而机器环境非东八)"
    else
      report INFO time/cn-calendar "$_cald(单日样本,证据偏弱;调休为内地特有实践)"
    fi
  elif [ "${_hev:-0}" -ge 3 ] && [ "${_mkev:-0}" -eq 0 ]; then
    if [ "$_tz_hit" = hit ]; then
      report INFO time/cn-calendar "法定假日(工作日)活跃 ${_hd} 天而调休补班日零活动 —— 不符合内地休假节奏(系统时区为陆港澳,声明与日历行为矛盾;亦可能值守/自由职业)"
    else
      report INFO time/cn-calendar "法定假日(工作日)活跃 ${_hd} 天 —— 假期仍工作,海外/自由职业节奏正常,不构成内地佐证"
    fi
  else
    report INFO time/cn-calendar "日历统计:补班日活跃 ${_mkev} 次/假日工作日 ${_hev} 次/工作日 ${_wdev} 次/周末 ${_wev} 次(混合模式,无明确指向)"
  fi

  # ── t7 附加:git 作者时区偏移直方图(计数为提交数,非仓库数) ──
  _tot7=0; _n8c=0
  if printf '%s\n' "$_tz7" | grep -q '[0-9]'; then
    _tot7=$(printf '%s\n' "$_tz7" | awk '{s+=$1} END{print s+0}')
    _n8c=$(printf '%s\n' "$_tz7" | grep ' +0800' | awk '{s+=$1} END{print s+0}')
    if [ "${_n8c:-0}" -gt 0 ] && [ -n "${TZ_CLASS:-}" ] && [ "${TZ_CLASS:-}" != CN ] && [ "${TZ_CLASS:-}" != HKMO ] && [ "${TZ_CLASS:-}" != E8 ]; then
      report SUSPICIOUS time/git-tz "git 提交作者时区含 +0800(共 $_n8c 条提交)而系统时区非东八 —— 作者本地环境残留"
    elif [ "${_n8c:-0}" -gt 0 ] && [ -z "${TZ_CLASS:-}" ]; then
      report INFO time/git-tz "git 作者时区偏移分布:$_n8c/$_tot7 条提交为 +0800(系统时区未探测,无法比对)"
    elif [ "${_n8c:-0}" -gt 0 ]; then
      report INFO time/git-tz "git 作者时区偏移分布:$_n8c/$_tot7 条提交为 +0800(与系统时区一致)"
    else
      report INFO time/git-tz "git 作者时区偏移分布:无 +0800 条目(共 $_tot7 条提交)"
    fi
  fi

  # ── 判定 3:复合升级(行为统计 + 独立记录性旁证 → 暴露级) ──
  # 单条作息不作暴露:东/东南亚 +7 时区(曼谷/雅加达/河内/珀斯)与 +8 在边界小时上原理性不可分;
  # 但「强统计矛盾 + 独立记录性 +8 证据」的复合,按既定 E8 政策(配置级 E8 矛盾 = 暴露)同权处理,
  # 残余误报为真正的 +8 非陆港澳用户(新加坡/马来西亚/台湾等),与 E8 规则同级。
  if [ "${_e8rel:-none}" != none ] && [ "${_tz_hit:-}" != hit ] && [ -n "${TZ_NAME:-}" ] \
     && [ -n "${_so:-}" ] && [ "${_conf:-}" = "高" ] && [ "${_ncl:-0}" -ge 60 ] \
     && awk "BEGIN{exit !(${_bs:-0} >= 0.85)}" && awk "BEGIN{exit !(${_d:-0} >= 1.5)}"; then
    _corr=""
    if [ "${_n8c:-0}" -ge 3 ]; then
      _corr="git 作者时区 +0800($_n8c 条提交,独立记录性证据)"
    elif [ "${_mkev:-0}" -ge 1 ] && [ "${_mkd:-0}" -ge 2 ] && [ "${_hev:-0}" -eq 0 ]; then
      _corr="内地调休日历遵循(补班日活跃 $_mkd 天且法定假日零活动,内地特有实践)"
    fi
    if [ -n "$_corr" ]; then
      report EXPOSED time/tz-consist-strong "作息区间 UTC+${_olo}–${_ohi}(得分 ${_bs},N=${_ncl},置信高)与系统时区 ${TZ_NAME}(UTC+${_so})偏差 ${_d}h,且有独立旁证:$_corr —— 行为与记录复合证据指向东八,时区设置无法解释实际使用节奏"
    fi
  fi
}
