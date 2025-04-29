#!/system/bin/sh

# load config
SCRIPT_DIR=${0%/*}
CONFIG_FILE="${SCRIPT_DIR}/config.cfg"
. "$CONFIG_FILE"
# log
LOG_PATH="${SCRIPT_DIR}/${LOG_NAME}"
log() {
  message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$message" >> "$LOG_PATH"
}
sleepy=0

get_app_name() {
  package_name="$1"

  # return if is lockscreen
  if [ "$package_name" = "NotificationShade" ]; then
    echo "锁屏"
    return
  fi

  cached_name=$(awk -F '=' -v pkg="$package_name" '$1 == pkg {print $2; exit}' "$CACHE")
  if [ -n "$cached_name" ]; then
    echo "$cached_name"
    #log "cache catch: $package_name=$cached_name"
    return
  fi

  # request mi getapps to get app name
  temp_file="${SCRIPT_DIR}/temp.html"
  if curl --silent --show-error --fail -A "Mozilla/5.0" -o "$temp_file" "https://app.mi.com/details?id=$package_name"; then
    app_name=$(sed -n 's/.*<title>\(.*\)<\/title>.*/\1/p' "$temp_file" | sed 's/-[^-]*$//')
    rm -f "$temp_file"

    if [ -n "$app_name" ]; then
      echo "$app_name"
      echo "$package_name=$app_name" >> "$CACHE"
      log "已写入缓存: $package_name=$app_name"
      return
    else
      echo "$package_name"
      log "网页解析失败，回退到包名: $package_name"
    fi
  else
    echo "$package_name"
    log "网页请求失败，回退到包名: $package_name"
  fi
}


send_status() {
  package_name="$1"
  app_name=$(get_app_name "$package_name")
  
  battery_level=$(dumpsys battery | sed -n 's/.*level: \([0-9]*\).*/\1/p')
  dumpsys_charging="$(dumpsys deviceidle get charging)"
  
  if [ "$dumpsys_charging" = "true" ]; then
    res_up="$app_name [充电中:$battery_level%]"
  else
    res_up="$app_name [电量:$battery_level%]"
  fi

  curl -s -k --connect-timeout 15 "{$URL}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"secret": "'"${SECRET}"'", "device": '"${DEVICE}"', "status": '"${using}"', "app": "'"$res_up"'"}'
}

# main
LAST_PACKAGE=""
> "$LOG_PATH"
log "service start"

sleep 10

while true; do
  isLock=$(dumpsys window policy | sed -n 's/.*showing=\([a-z]*\).*/\1/p')
  echo "isLock: $isLock"
  if [ "$isLock" = "true" ]; then
    sleepy=$((sleepy + 1))
    log "锁屏: $sleepy"
    PACKAGE_NAME="NotificationShade"
      # sleep detect
      if [ "$sleepy" -ge 60 ]; then
         using=0
         log "sleeping"
         send_status "$PACKAGE_NAME"
         sleepy=0
      else
        using=1
      fi
  else
    sleepy=0
    using=1
    CURRENT_FOCUS=$(dumpsys activity activities 2>/dev/null | grep -m 1 'ResumedActivity')
    PACKAGE_NAME=$(echo "$CURRENT_FOCUS" | sed -E 's/.*u0 ([^/]+).*/\1/')
  fi

  # 常规状态更新
  if [ -n "$PACKAGE_NAME" ] && [ "$PACKAGE_NAME" != "$LAST_PACKAGE" ]; then
    log "状态更新: ${LAST_PACKAGE:-none} → ${PACKAGE_NAME}"
    send_status "$PACKAGE_NAME"
    LAST_PACKAGE="$PACKAGE_NAME"
  fi
  
  sleep 120
done
