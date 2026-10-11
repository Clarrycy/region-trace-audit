# macOS read-only helpers. Subshells keep scratch variables out of check functions.
mac_console_user() (
  _cu=$(printf 'show State:/Users/ConsoleUser\n' | scutil 2>/dev/null |
    awk '$1=="Name" && $2==":" {print $3; exit}')
  case "$_cu" in ''|loginwindow|root|_mbsetupuser) return 1 ;; *) printf '%s\n' "$_cu" ;; esac
)

mac_boot_epoch() {
  sysctl -n kern.boottime 2>/dev/null |
    sed -n 's/.*{[[:space:]]*sec = \([0-9][0-9]*\),.*/\1/p'
}

mac_dns_servers() {
  scutil --dns 2>/dev/null |
    awk '$1 ~ /^nameserver\[[0-9]+\]$/ && $2==":" && !seen[$3]++ {print $3}'
}

mac_wifi_interfaces() {
  networksetup -listallhardwareports 2>/dev/null |
    awk '/^Hardware Port:/ {wifi=($0 ~ /Wi-Fi|AirPort/)} wifi && /^Device:/ {print $2}'
}

# Match bundle-id components, not substrings: com.todesktop is not ToDesk.
mac_cn_labels() {
  grep -iE '(^|\.)(tencent|qq|weixin|wechat|baidu|netease|alibaba|aliyun|dingtalk|sunlogin|todesk|iqiyi|youku|bilibili)(\.|$)'
}
