#!/bin/bash
# mac-check: quick health check for a used Apple silicon Mac before you buy it.
#
#   curl -sL https://sybili.github.io/mac-health | bash
#
# The automatic part only reads: nothing is installed or sent anywhere, and no
# admin password is needed. The optional hands-on tests show full-screen
# colours and the live camera image, play test tones and
# record a short clip that is deleted after playback. macOS asks once whether
# Terminal may use the camera and microphone. A muted or very low volume is
# raised for the tests and restored afterwards. Runs on the stock /bin/bash 3.2.
#
# Everything lives inside main() so bash parses the whole file before running
# anything: safe when the script is piped straight from curl.

VERSION="1.3.0"

usage() {
  cat <<'EOF'
mac-check: quick health check for a used Apple silicon Mac.

Usage:
  curl -sL https://sybili.github.io/mac-health | bash
  curl -sL https://sybili.github.io/mac-health | bash -s -- --quick
  bash mac-check.sh [--quick] [--no-color] [--help] [--version]

Reads hardware, battery, storage and lock state, runs screen, camera,
speaker and microphone tests with you, then prints a health score (0-100)
and a buy / don't-buy verdict.

  --quick     skip the hands-on tests
  --no-color  plain output
EOF
}

# ---------- output helpers ----------

setup_colors() {
  if [ "$USE_COLOR" = 1 ]; then
    RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'
    BLD=$'\033[1m'; DIM=$'\033[2m'; RST=$'\033[0m'
  else
    RED=; GRN=; YEL=; CYN=; BLD=; DIM=; RST=
  fi
}

section() { printf '\n%s%s%s\n' "$BLD$CYN" "$1" "$RST"; }

# row <ok|warn|bad|stop|info|na> <label> <value> [hint]
row() {
  local tag
  case "$1" in
    ok)   tag="${GRN}  OK  ${RST}" ;;
    warn) tag="${YEL} WARN ${RST}" ;;
    bad)  tag="${RED} FAIL ${RST}" ;;
    stop) tag="${RED}${BLD} STOP ${RST}" ;;
    info) tag="${DIM} INFO ${RST}" ;;
    *)    tag="${DIM}  --  ${RST}" ;;
  esac
  printf ' [%s] %-22s %s\n' "$tag" "$2" "$3"
  [ -n "$4" ] && printf '          %-22s %s-> %s%s\n' "" "$DIM" "$4" "$RST"
}

deduct()  { SCORE=$((SCORE - $1)); DEDUCTIONS+=("$2 (-$1)"); }
blocker() { BLOCKERS+=("$1"); }
# A worn battery is a replaceable part, so all battery findings together cost
# at most 35 points instead of stacking up and burying a healthy machine.
bat_deduct() {
  local pts=$1 room=$((35 - BAT_PTS))
  [ "$pts" -gt "$room" ] && pts=$room
  [ "$pts" -gt 0 ] || return 0
  BAT_PTS=$((BAT_PTS + pts)); deduct "$pts" "$2"
}

# ---------- parsing helpers ----------

# jv <json> <key>: first scalar value of "key" in system_profiler -json output.
# system_profiler prints one key per line, so a line match is enough, and the
# keys stay English even when macOS runs in another language.
jv() {
  printf '%s\n' "$1" | awk -v k="\"$2\"" '{
    s = $0; sub(/^[ \t]+/, "", s)
    if (index(s, k) != 1) next
    s = substr(s, length(k) + 1)
    if (s !~ /^[ \t]*:/) next
    sub(/^[ \t]*:[ \t]*/, "", s); sub(/,[ \t]*$/, "", s); gsub(/^"|"$/, "", s)
    print s; exit
  }'
}

# iv <ioreg-output> <key>: top-level value of "key" = value in ioreg output.
iv() {
  printf '%s\n' "$1" | awk -v k="\"$2\" = " '{
    i = index($0, k); if (!i) next
    s = substr($0, i + length(k)); gsub(/^"|"$/, "", s); print s; exit
  }'
}

is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# ---------- checks ----------

collect() {
  printf '%sReading system information (takes a few seconds)...%s\n' "$DIM" "$RST"
  HW=$(system_profiler -json SPHardwareDataType 2>/dev/null)
  PWR=$(system_profiler -json SPPowerDataType 2>/dev/null)
  DISP=$(system_profiler -json SPDisplaysDataType 2>/dev/null)
  CAM=$(system_profiler -json SPCameraDataType 2>/dev/null)
  BT=$(system_profiler -json SPBluetoothDataType 2>/dev/null)
  AUD=$(system_profiler -json SPAudioDataType 2>/dev/null)
  CFG=$(system_profiler -json SPConfigurationProfileDataType 2>/dev/null)
  BAT=$(ioreg -rn AppleSmartBattery -w0 2>/dev/null)
  DISK=$(diskutil info disk0 2>/dev/null)

  MODEL_ID=$(jv "$HW" machine_model)
  MACHINE=$(jv "$HW" machine_name)
  PRODUCT=$(ioreg -rc IOPlatformDevice -k product-name -w0 2>/dev/null \
    | awk -F'<"|">' '/"product-name"/ { print $2; exit }')
  [ -z "$PRODUCT" ] && PRODUCT="$MACHINE ($MODEL_ID)"
  case "$MACHINE" in *MacBook*) LAPTOP=1 ;; *) LAPTOP=0 ;; esac
  YEAR=$(printf '%s' "$PRODUCT" | grep -oE '20[0-9]{2}' | tail -1)
  NOW_YEAR=$(date +%Y)
}

check_identity() {
  section "MACHINE"
  local serial os build setup age=""
  RAM=$(jv "$HW" physical_memory)
  serial=$(jv "$HW" serial_number)
  os=$(sw_vers -productVersion 2>/dev/null); build=$(sw_vers -buildVersion 2>/dev/null)
  DISK_GB=$(printf '%s\n' "$DISK" | awk -F'[(]' '/Disk Size:/ { split($2, a, " "); printf "%d", a[1] / 1e9 + 0.5; exit }')
  setup=$(stat -f '%Sm' -t '%Y-%m-%d' /var/db/.AppleSetupDone 2>/dev/null)
  [ -n "$YEAR" ] && age=" (released $YEAR, ~$((NOW_YEAR - YEAR)) years old)"

  row info "Model" "$PRODUCT"
  row info "Identifier" "$MODEL_ID$age"
  row info "Chip" "$(jv "$HW" chip_type)"
  row info "Memory" "$RAM"
  [ -n "$DISK_GB" ] && row info "Storage" "$DISK_GB GB"
  row info "Serial number" "$serial" "Compare with the box, invoice and bottom case; check at checkcoverage.apple.com"
  row info "macOS" "$os ($build)"
  [ -n "$setup" ] && row info "macOS set up on" "$setup" "A recent date means the Mac was recently erased"
}

check_locks() {
  section "LOCKS & OWNERSHIP"

  local act; act=$(jv "$HW" activation_lock_status)
  case "$act" in
    *disabled*) row ok "Activation Lock" "Disabled" ;;
    *enabled*)
      row stop "Activation Lock" "ENABLED" "Seller must sign out of their Apple Account, then re-run this check"
      blocker "Activation Lock is ON: the Mac is locked to the seller's Apple Account" ;;
    *) row na "Activation Lock" "Unknown" "Check that Find My Mac is turned off" ;;
  esac

  # Apple Account / Find My for the logged-in user (never print the address)
  local accts fmm
  accts=$(defaults read MobileMeAccounts Accounts 2>/dev/null)
  if printf '%s' "$accts" | grep -q 'AccountID'; then
    if printf '%s\n' "$accts" | grep -B1 'FIND_MY_MAC' | grep -q 'Enabled = 1'; then fmm="Find My Mac ON"; else fmm="Find My Mac off"; fi
    row warn "Apple Account" "Signed in ($fmm)" "Seller must sign out before handover"
  else
    row ok "Apple Account" "Not signed in (this user)"
  fi

  # MDM / company enrollment
  local enr dep mdm
  enr=$(profiles status -type enrollment 2>/dev/null)
  dep=$(printf '%s\n' "$enr" | awk -F': ' '/DEP/ { print $2; exit }')
  mdm=$(printf '%s\n' "$enr" | awk -F': ' '/MDM enrollment/ { print $2; exit }')
  case "$mdm" in
    Yes*) row stop "MDM enrollment" "$mdm" "Managed by a company: it can lock or wipe this Mac remotely"
          blocker "Mac is enrolled in company device management (MDM)" ;;
    No*)  row ok "MDM enrollment" "No" ;;
    *)    row na "MDM enrollment" "Unknown" "Check System Settings > General > Device Management" ;;
  esac

  # Apple Business Manager record: the Mac re-enrolls into company MDM after a reset
  local cc=/var/db/ConfigurationProfiles/Settings
  if [ "$dep" = Yes ] || [ -e "$cc/.cloudConfigHasActivationRecord" ] || [ -e "$cc/.cloudConfigRecordFound" ]; then
    row stop "Company registration" "Registered to an organization (DEP/ABM)" "It will lock itself to the company again after an erase"
    blocker "Mac is registered in Apple Business Manager (DEP): it belongs to a company"
  elif [ -e "$cc/.cloudConfigNoActivationRecord" ]; then
    row ok "Company registration" "None found"
  else
    row na "Company registration" "Not recorded"
  fi

  # Traces left by MDM-bypass tools sold with ex-corporate Macs
  if grep -v '^[[:space:]]*#' /etc/hosts 2>/dev/null \
      | grep -qiE 'deviceenrollment\.apple\.com|mdmenrollment\.apple\.com|iprofiles\.apple\.com|acmdm\.apple\.com|albert\.apple\.com'; then
    row stop "MDM bypass" "Apple enrollment servers blocked in /etc/hosts" "Classic sign of a bypassed company or locked Mac"
    blocker "MDM bypass detected: Apple enrollment servers are blocked"
  elif [ -e "$cc/.cloudConfigProfileInstalled" ] && [ -e "$cc/.cloudConfigRecordNotFound" ] \
      && [ "${mdm%% *}" = No ]; then
    # Bypass scripts fake a finished enrollment while no MDM is actually present
    row warn "MDM bypass" "Possible bypass traces" "Ask the seller where the Mac comes from"
    deduct 15 "Possible MDM bypass traces"
  else
    row ok "MDM bypass" "No traces found"
  fi

  # Configuration profiles (provisioning profiles of normal apps don't count)
  if printf '%s' "$CFG" | grep -oE 'spconfigprofile_section_[a-z]+' | grep -qv provprofiles; then
    local orgs
    orgs=$(printf '%s\n' "$CFG" | awk -F'" : "' '/"spconfigprofile_organization"/ { sub(/",?$/, "", $2); print $2 }' | sort -u | paste -sd, - | sed 's/,/, /g')
    row warn "Config profiles" "Installed${orgs:+ ($orgs)}" "Should be removed before handover"
    deduct 5 "Configuration profiles installed"
  else
    row ok "Config profiles" "None"
  fi

  local sip; sip=$(csrutil status 2>/dev/null)
  case "$sip" in
    *"status: enabled."*) row ok "System Integrity" "SIP enabled" ;;
    *disabled*|*Custom*) row warn "System Integrity" "SIP disabled or modified" "Unusual: often a sign of tinkering or bypass tools"
                         deduct 10 "System Integrity Protection disabled" ;;
    *) row na "System Integrity" "Unknown" ;;
  esac

  # Virtual machine: you'd be looking at fake hardware
  if [ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ]; then
    row stop "Virtual machine" "YES" "This is not the real hardware"
    blocker "Running inside a virtual machine"
  fi
}

check_battery() {
  section "BATTERY"
  if [ "$(iv "$BAT" BatteryInstalled)" != Yes ]; then
    row na "Battery" "No battery (desktop Mac)"
    return
  fi

  local cond cycles rated cap design rawmax nominal pf temp hours watts conn
  cond=$(jv "$PWR" sppower_battery_health)
  cycles=$(jv "$PWR" sppower_battery_cycle_count)
  is_int "$cycles" || cycles=$(iv "$BAT" CycleCount)
  rated=$(iv "$BAT" DesignCycleCount9C); is_int "$rated" && [ "$rated" -gt 0 ] || rated=1000
  design=$(iv "$BAT" DesignCapacity)
  rawmax=$(iv "$BAT" AppleRawMaxCapacity)
  nominal=$(iv "$BAT" NominalChargeCapacity)
  cap=$(jv "$PWR" sppower_battery_health_maximum_capacity | tr -dc '0-9')
  if ! is_int "$cap" && is_int "$design" && [ "$design" -gt 0 ]; then
    local full="$nominal"; is_int "$full" || full="$rawmax"
    is_int "$full" && cap=$((full * 100 / design))
  fi
  pf=$(iv "$BAT" PermanentFailureStatus)
  temp=$(iv "$BAT" Temperature)
  hours=$(printf '%s' "$BAT" | grep -oE '"TotalOperatingTime"=[0-9]+' | head -1 | cut -d= -f2)
  watts=$(jv "$PWR" sppower_ac_charger_watts)
  conn=$(jv "$PWR" sppower_battery_charger_connected)

  # Condition reported by macOS
  case "$(printf '%s' "$cond" | tr '[:upper:]' '[:lower:]')" in
    good|normal) row ok "Condition" "$cond" ;;
    "")          row na "Condition" "Not reported" ;;
    *service*|*poor*|*replace\ now*|*check*)
      row bad "Condition" "$cond" "Battery needs replacing"
      bat_deduct 25 "Battery condition: $cond" ;;
    *) row warn "Condition" "$cond"; bat_deduct 10 "Battery condition: $cond" ;;
  esac

  # Maximum capacity
  if is_int "$cap"; then
    local mah=""; is_int "$rawmax" && is_int "$design" && mah=" ($rawmax of $design mAh)"
    if   [ "$cap" -ge 90 ]; then row ok   "Max capacity" "$cap %$mah"
    elif [ "$cap" -ge 85 ]; then row ok   "Max capacity" "$cap %$mah"; bat_deduct 5 "Battery at $cap % capacity"
    elif [ "$cap" -ge 80 ]; then row warn "Max capacity" "$cap %$mah" "Getting close to the 80 % replacement point"
                                 bat_deduct 12 "Battery at $cap % capacity"
    else row bad "Max capacity" "$cap %$mah" "Below 80 %: replacement due"
         bat_deduct 25 "Battery at $cap % capacity"
    fi
  else
    row na "Max capacity" "Not reported"
  fi

  # Cycle count relative to the rated cycles
  if is_int "$cycles"; then
    local pct=$((cycles * 100 / rated))
    if   [ "$pct" -lt 30 ];  then row ok   "Cycle count" "$cycles of $rated rated"
    elif [ "$pct" -lt 60 ];  then row ok   "Cycle count" "$cycles of $rated rated"; bat_deduct 3 "$cycles battery cycles"
    elif [ "$pct" -lt 80 ];  then row warn "Cycle count" "$cycles of $rated rated"; bat_deduct 8 "$cycles battery cycles"
    elif [ "$pct" -le 100 ]; then row warn "Cycle count" "$cycles of $rated rated" "Near end of rated life"; bat_deduct 15 "$cycles battery cycles"
    else row bad "Cycle count" "$cycles of $rated rated" "Past rated life"; bat_deduct 20 "$cycles battery cycles"
    fi
  fi

  # Battery age from the gauge's own operating-time counter (hours). It
  # survives macOS reinstalls, unlike anything the seller can reset.
  BAT_YEARS10=""
  if is_int "$hours" && [ "$hours" -gt 0 ] && [ "$hours" -lt 200000 ]; then
    BAT_YEARS10=$((hours * 10 / 8766))
    local note=""
    if [ -n "$YEAR" ] && [ $(( (NOW_YEAR - YEAR) * 10 - BAT_YEARS10 )) -ge 20 ]; then
      note="Younger than the model: bought new later, or battery replaced (ask)"
    fi
    row info "Battery age" "~$((BAT_YEARS10 / 10)).$((BAT_YEARS10 % 10)) years in service" "$note"
    if is_int "$cycles" && [ "$BAT_YEARS10" -ge 10 ]; then
      row info "Usage rate" "~$((cycles * 10 / BAT_YEARS10)) cycles per year"
    fi
  fi

  if [ -n "$pf" ] && [ "$pf" != 0 ]; then
    row bad "Failure flag" "Permanent failure reported ($pf)"
    bat_deduct 30 "Battery reports a permanent failure"
  fi

  if is_int "$temp"; then
    local c=$((temp / 100))
    if [ "$c" -ge 45 ]; then row warn "Temperature" "$c C" "Hot: let it cool down and check again"
    else row ok "Temperature" "$c C"; fi
  fi

  if [ "$conn" = TRUE ]; then
    row ok "Charger" "Connected${watts:+ ($watts W)}" "Try every USB-C/MagSafe port with it"
  else
    row info "Charger" "Not connected" "Plug in the seller's charger and check it charges"
  fi

  # Rough outlook: years until 80 % capacity at the wear rate so far
  if is_int "$cap" && [ "$cap" -gt 80 ] && [ "$cap" -lt 100 ]; then
    local years10="$BAT_YEARS10" src="battery age"
    if [ -z "$years10" ] && [ -n "$YEAR" ]; then years10=$(( (NOW_YEAR - YEAR) * 10 )); src="model age"; fi
    if [ -n "$years10" ] && [ "$years10" -ge 5 ]; then
      local left10=$(( (cap - 80) * years10 / (100 - cap) ))
      OUTLOOK="Battery reaches 80 % in ~$((left10 / 10)).$((left10 % 10)) years at the current wear rate (based on $src)"
    fi
  fi
}

check_storage() {
  section "STORAGE"
  if [ -z "$DISK" ]; then row na "Internal SSD" "Not readable"; return; fi
  local name smart
  name=$(printf '%s\n' "$DISK" | awk -F': *' '/Device \/ Media Name/ { print $2; exit }')
  smart=$(printf '%s\n' "$DISK" | awk -F': *' '/SMART Status/ { print $2; exit }')
  row info "Drive" "$name${DISK_GB:+, $DISK_GB GB}"
  case "$smart" in
    Verified) row ok "SMART status" "Verified" ;;
    *Fail*)   row bad "SMART status" "$smart" "The SSD is failing and is soldered to the logic board"
              deduct 40 "SSD SMART status: $smart"; blocker "SSD reports SMART failure" ;;
    *)        row na "SMART status" "${smart:-Not reported}" ;;
  esac

  # Wear details only if smartmontools happens to be installed
  if command -v smartctl >/dev/null 2>&1; then
    local sm used written hrs
    sm=$(smartctl -a disk0 2>/dev/null)
    used=$(printf '%s\n' "$sm" | awk -F': *' '/Percentage Used/ { print $2; exit }' | tr -dc '0-9')
    written=$(printf '%s\n' "$sm" | awk -F'[][]' '/Data Units Written/ { print $2; exit }')
    hrs=$(printf '%s\n' "$sm" | awk -F': *' '/Power On Hours/ { print $2; exit }')
    if is_int "$used"; then
      if [ "$used" -ge 80 ]; then row bad "SSD wear" "$used % used"; deduct 25 "SSD wear $used %"
      elif [ "$used" -ge 30 ]; then row warn "SSD wear" "$used % used"; deduct 8 "SSD wear $used %"
      else row ok "SSD wear" "$used % used"; fi
    fi
    [ -n "$written" ] && row info "Data written" "$written"
    [ -n "$hrs" ] && row info "Power-on hours" "$hrs"
  fi
}

check_hardware() {
  section "BUILT-IN HARDWARE (detected by macOS)"

  if [ "$LAPTOP" = 1 ]; then
    if printf '%s' "$DISP" | grep -qE 'spdisplays_internal|spdisplays_built-in'; then
      row ok "Internal display" "Detected"
    else
      row bad "Internal display" "NOT detected"; deduct 30 "Internal display not detected"
    fi
    if ioreg -r -c IOHIDDevice -w0 2>/dev/null | grep -q '"Product" = "Apple Internal Keyboard'; then
      row ok "Keyboard/trackpad" "Detected"
    else
      row bad "Keyboard/trackpad" "NOT detected"; deduct 20 "Built-in keyboard/trackpad not detected"
    fi
  fi

  # Skip Continuity Camera (a nearby iPhone/iPad shows up as a camera too)
  local cams
  cams=$(printf '%s\n' "$CAM" | awk -F'" : "' '
    /"_name"/ { name = $2; sub(/",?$/, "", name) }
    /"spcamera_model-id"/ { if ($2 !~ /iPhone|iPad/) { print name; exit } }')
  if [ -n "$cams" ]; then row ok "Camera" "$cams"
  elif [ "$LAPTOP" = 1 ]; then row bad "Camera" "NOT detected"; deduct 10 "Camera not detected"
  else row na "Camera" "None"; fi

  if ioreg -rc IO80211Controller -d1 2>/dev/null | grep -q '+-o'; then
    row ok "Wi-Fi" "Detected"
  else
    row bad "Wi-Fi" "NOT detected"; deduct 15 "Wi-Fi hardware not detected"
  fi

  if printf '%s' "$BT" | grep -q 'controller_chipset\|controller_state'; then
    row ok "Bluetooth" "Detected"
  else
    row bad "Bluetooth" "NOT detected"; deduct 10 "Bluetooth not detected"
  fi

  # Built-in audio: a device whose transport is "builtin", split by in/out
  local audio spk mic
  audio=$(printf '%s\n' "$AUD" | awk '
    /"_name"/ { inp = 0; out = 0 }
    /"coreaudio_device_input"/  { inp = 1 }
    /"coreaudio_device_output"/ { out = 1 }
    /coreaudio_device_type_builtin/ { if (out) spk = 1; if (inp) mic = 1 }
    END { print (spk ? 1 : 0) " " (mic ? 1 : 0) }')
  spk=${audio% *}; mic=${audio#* }
  if [ "$spk" = 1 ]; then row ok "Speakers" "Detected"
  elif [ "$LAPTOP" = 1 ]; then row bad "Speakers" "NOT detected"; deduct 5 "Built-in speakers not detected"; fi
  if [ "$mic" = 1 ]; then row ok "Microphone" "Detected"
  elif [ "$LAPTOP" = 1 ]; then row bad "Microphone" "NOT detected"; deduct 5 "Built-in microphone not detected"; fi
}

check_stability() {
  section "STABILITY"
  local dir=/Library/Logs/DiagnosticReports
  if [ -r "$dir" ]; then
    local panics n last
    panics=$(find "$dir" -maxdepth 2 -type f -iname '*panic*' 2>/dev/null)
    n=$(printf '%s' "$panics" | grep -c .)
    if [ "$n" -eq 0 ]; then
      row ok "Kernel panics" "None logged"
    else
      last=$(printf '%s\n' "$panics" | while IFS= read -r f; do stat -f '%Sm' -t '%Y-%m-%d' "$f"; done | sort | tail -1)
      if [ "$n" -ge 4 ]; then row bad "Kernel panics" "$n logged (last $last)" "Frequent crashes can mean a hardware fault"; deduct 20 "$n kernel panics logged"
      elif [ "$n" -ge 2 ]; then row warn "Kernel panics" "$n logged (last $last)"; deduct 10 "$n kernel panics logged"
      else row warn "Kernel panics" "1 logged ($last)"; deduct 5 "1 kernel panic logged"; fi
    fi
  else
    row na "Kernel panics" "Logs not readable (non-admin user)"
  fi

  # pmset prints "No ... warning level has been recorded" when all is well,
  # and CPU_Speed_Limit drops below 100 while the CPU is throttled.
  local therm; therm=$(pmset -g therm 2>/dev/null)
  if printf '%s\n' "$therm" | awk '
      /warning level/ && !/No (thermal|performance) warning level/ { hit = 1 }
      /CPU_Speed_Limit/ { v = $NF + 0; if (v < 100) hit = 1 }
      END { exit !hit }'; then
    row warn "Thermals" "Throttling or thermal warning active" "Check fans and vents for dust"
    deduct 5 "Thermal warning"
  else
    row ok "Thermals" "No thermal warning"
  fi
}

# ---------- hands-on tests ----------
#
# The test windows and sounds are small JavaScript for Automation programs
# run by osascript, so nothing has to be installed. Each block is loaded with
# read -d '' (not $(cat <<...)) because bash 3.2 mis-parses quotes inside a
# here-document in a command substitution.

# Full-screen colour test on every connected screen. A borderless,
# non-activating panel gets key presses even though osascript was started
# from the Terminal. Click or any key: next colour. Esc: stop.
IFS= read -r -d '' DISPLAY_JS <<'JS'
ObjC.import('Cocoa');
function run() {
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(0);
  var colors = [[1, 1, 1], [0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1], [0.5, 0.5, 0.5]];
  var idx = 0, wins = [];
  function paint() {
    var c = colors[idx], col = $.NSColor.colorWithSRGBRedGreenBlueAlpha(c[0], c[1], c[2], 1);
    wins.forEach(function (w) { w.setBackgroundColor(col); });
  }
  function next() { if (++idx >= colors.length) done(); else paint(); }
  function done() { $.NSCursor.unhide; app.terminate(null); }
  ObjC.registerSubclass({
    name: 'MCColorPanel', superclass: 'NSPanel',
    methods: {
      'canBecomeKeyWindow': { types: ['bool', []], implementation: function () { return true; } },
      'acceptsFirstMouse:': { types: ['bool', ['id']], implementation: function () { return true; } },
      'keyDown:': { types: ['void', ['id']], implementation: function (e) { if (e.keyCode == 53) done(); else next(); } },
      'mouseDown:': { types: ['void', ['id']], implementation: function () { next(); } }
    }
  });
  ObjC.registerSubclass({
    name: 'MCTimeout', superclass: 'NSObject',
    methods: { 'fire:': { types: ['void', ['id']], implementation: function () { done(); } } }
  });
  var screens = $.NSScreen.screens;
  for (var i = 0; i < screens.count; i++) {
    var w = $.MCColorPanel.alloc.initWithContentRectStyleMaskBackingDefer(screens.objectAtIndex(i).frame, 128, 2, false);
    w.setLevel(1000);                  // above menu bar and Dock
    w.setCollectionBehavior(1 | 256);  // all Spaces, also over full-screen apps
    w.setHidesOnDeactivate(false);
    wins.push(w);
  }
  paint();
  wins.forEach(function (w, n) { if (n === 0) w.makeKeyAndOrderFront(null); else w.orderFrontRegardless; });
  app.activateIgnoringOtherApps(true);
  $.NSCursor.hide;
  // Never leave the screen covered: give up after 5 minutes
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(300, $.MCTimeout.alloc.init, 'fire:', null, false);
  app.run;
}
JS

# Camera access and live preview. "status <vide|soun>" and "auth <vide|soun>"
# print the permission state (3 = allowed); "show" opens the live image.
IFS= read -r -d '' CAPTURE_JS <<'JS'
ObjC.import('Cocoa');
ObjC.import('AVFoundation');
// The capture classes live in a sub-framework without scripting metadata,
// so look them up by name.
function cls(name) { return $.NSClassFromString(name); }
function out(s) {
  $.NSFileHandle.fileHandleWithStandardOutput.writeData($(s + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
}
// 0 not asked yet, 1 restricted, 2 denied, 3 allowed
function status(type) { return Number(cls('AVCaptureDevice').authorizationStatusForMediaType(type)); }
function device(type) {
  if (type === 'vide') {
    var found = cls('AVCaptureDeviceDiscoverySession').discoverySessionWithDeviceTypesMediaTypePosition(
      $(['AVCaptureDeviceTypeBuiltInWideAngleCamera']), 'vide', 0).devices;
    if (found.count > 0) return found.objectAtIndex(0);
  }
  return cls('AVCaptureDevice').defaultDeviceWithMediaType(type);
}
// Opening the device makes macOS show its permission prompt once; then wait
// (up to a minute) for the answer.
function auth(type) {
  var st = status(type);
  if (st !== 0) return st;
  var dev = device(type);
  if (!dev || dev.isNil()) return -1;
  var session = cls('AVCaptureSession').alloc.init;
  var input = cls('AVCaptureDeviceInput').deviceInputWithDeviceError(dev, null);
  if (input && !input.isNil() && session.canAddInput(input)) session.addInput(input);
  session.startRunning;
  for (var i = 0; i < 600 && st === 0; i++) { delay(0.1); st = status(type); }
  session.stopRunning;
  return st;
}
// Live camera image in a window; click or any key closes it.
function show() {
  var dev = device('vide');
  if (!dev || dev.isNil()) return out('nocamera');
  if (status('vide') !== 3) return out('denied');
  var input = cls('AVCaptureDeviceInput').deviceInputWithDeviceError(dev, null);
  var session = cls('AVCaptureSession').alloc.init;
  if (!input || input.isNil() || !session.canAddInput(input)) return out('fail');
  session.addInput(input);

  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(0);
  var closed = false;
  function close() {
    if (closed) return;
    closed = true; session.stopRunning; out('ok'); app.terminate(null);
  }
  ObjC.registerSubclass({
    name: 'MCCamPanel', superclass: 'NSPanel',
    methods: {
      'canBecomeKeyWindow': { types: ['bool', []], implementation: function () { return true; } },
      'acceptsFirstMouse:': { types: ['bool', ['id']], implementation: function () { return true; } },
      'keyDown:': { types: ['void', ['id']], implementation: function () { close(); } },
      'mouseDown:': { types: ['void', ['id']], implementation: function () { close(); } }
    }
  });
  ObjC.registerSubclass({
    name: 'MCCamHelper', superclass: 'NSObject',
    methods: { 'close:': { types: ['void', ['id']], implementation: function () { close(); } } }
  });

  var W = 720, H = 500, CAP = 52, s = $.NSScreen.mainScreen.visibleFrame;
  var win = $.MCCamPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(s.origin.x + (s.size.width - W) / 2, s.origin.y + (s.size.height - H) / 2, W, H), 128, 2, false);
  win.setLevel(1000); win.setCollectionBehavior(1 | 256); win.setHidesOnDeactivate(false);
  win.setBackgroundColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.11, 0.11, 0.12, 1));
  var content = win.contentView;

  var video = $.NSView.alloc.initWithFrame($.NSMakeRect(0, CAP, W, H - CAP));
  video.setWantsLayer(true);
  var layer = cls('AVCaptureVideoPreviewLayer').layerWithSession(session);
  layer.setFrame(video.bounds);
  layer.setVideoGravity('AVLayerVideoGravityResizeAspect');
  video.layer.addSublayer(layer);
  content.addSubview(video);

  var caption = $.NSTextField.wrappingLabelWithString('Live image from ' + ObjC.unwrap(dev.localizedName) +
    '. Check it is sharp with natural colours and that the green light next to the camera is on. ' +
    'Click or press any key to close.');
  caption.setFrame($.NSMakeRect(16, 6, W - 32, CAP - 10));
  caption.setFont($.NSFont.systemFontOfSize(12));
  caption.setTextColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.8, 0.8, 0.82, 1));
  content.addSubview(caption);

  session.startRunning;
  win.makeKeyAndOrderFront(null);
  app.activateIgnoringOtherApps(true);
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(30, $.MCCamHelper.alloc.init, 'close:', null, false);
  app.run;
}
function run(argv) {
  if (argv[0] === 'status') return String(status(argv[1]));
  if (argv[0] === 'auth') return String(auth(argv[1]));
  show();
}
JS

# Sounds and recording. "left"/"right": three chimes panned fully to one
# side. "sweep": a rising tone from 60 Hz to 10 kHz on both sides, which makes
# rattles and crackling easy to hear. "record <file>": 4 seconds from the
# microphone, prints "ok <peak dB>". "play <file>": plays a recording back.
IFS= read -r -d '' AUDIO_JS <<'JS'
ObjC.import('AVFoundation');
function wav(seconds, fn) {
  var rate = 22050, n = Math.floor(seconds * rate), len = 44 + n * 2, b = new Array(len), i;
  function str(o, s) { for (var k = 0; k < s.length; k++) b[o + k] = s.charCodeAt(k); }
  function u16(o, v) { b[o] = v & 255; b[o + 1] = (v >> 8) & 255; }
  function u32(o, v) { u16(o, v & 65535); u16(o + 2, (v >>> 16) & 65535); }
  str(0, 'RIFF'); u32(4, len - 8); str(8, 'WAVEfmt '); u32(16, 16); u16(20, 1); u16(22, 1);
  u32(24, rate); u32(28, rate * 2); u16(32, 2); u16(34, 16); str(36, 'data'); u32(40, n * 2);
  for (i = 0; i < n; i++) {
    var v = Math.round(Math.max(-1, Math.min(1, fn(i / rate))) * 32767);
    u16(44 + i * 2, v < 0 ? v + 65536 : v);
  }
  var abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/', out = [];
  for (i = 0; i < len; i += 3) {
    var x = (b[i] << 16) | ((b[i + 1] || 0) << 8) | (b[i + 2] || 0);
    out.push(abc[x >> 18 & 63] + abc[x >> 12 & 63] + (i + 1 < len ? abc[x >> 6 & 63] : '=') + (i + 2 < len ? abc[x & 63] : '='));
  }
  return out.join('');
}
function play(player, seconds) {
  if (!player || player.isNil() || !player.play) return 'fail';
  delay(seconds + 0.2);
  return 'ok';
}
// Records 4 seconds from the default input and prints "ok <peak dB>".
function record(path) {
  var settings = $({ AVFormatIDKey: 1819304813, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false });
  var rec = $.AVAudioRecorder.alloc.initWithURLSettingsError($.NSURL.fileURLWithPath(path), settings, null);
  if (!rec || rec.isNil()) return 'fail';
  rec.setMeteringEnabled(true);
  if (!rec.record) return 'fail';
  var peak = -160;
  for (var i = 0; i < 40; i++) {
    delay(0.1); rec.updateMeters;
    peak = Math.max(peak, rec.peakPowerForChannel(0));
  }
  rec.stop;
  return 'ok ' + Math.round(peak);
}
function run(argv) {
  var mode = argv[0], T, fn, pan = 0;
  if (mode === 'record') return record(argv[1]);
  if (mode === 'play') {
    var p = $.AVAudioPlayer.alloc.initWithContentsOfURLError($.NSURL.fileURLWithPath(argv[1]), null);
    return play(p, p.isNil() ? 0 : p.duration);
  }
  if (mode === 'sweep') {
    T = 4;
    var f0 = 60, f1 = 10000, k = Math.log(f1 / f0);
    fn = function (t) {
      return 0.5 * Math.min(1, t / 0.05, (T - t) / 0.05) * Math.sin(2 * Math.PI * f0 * T / k * (Math.exp(t / T * k) - 1));
    };
  } else {
    T = 1.5; pan = mode === 'left' ? -1 : 1;
    fn = function (t) {
      var p = t % 0.5; if (p > 0.35) return 0;
      var env = Math.min(1, p / 0.01) * Math.exp(-p * 8);
      return 0.6 * env * (Math.sin(2 * Math.PI * 660 * t) + 0.4 * Math.sin(2 * Math.PI * 1320 * t));
    };
  }
  var data = $.NSData.alloc.initWithBase64EncodedStringOptions(wav(T, fn), 0);
  var player = $.AVAudioPlayer.alloc.initWithDataError(data, null);
  if (!player || player.isNil()) return 'fail';
  player.setPan(pan);
  return play(player, T);
}
JS

have_tty() { (exec </dev/tty) 2>/dev/null; }

# Drops keys that reached the Terminal while a test window was open, so they
# can't be read as the answer to the next question.
flush_tty() {
  local old; old=$(stty -g </dev/tty 2>/dev/null) || return 0
  # Non-blocking read of whatever is waiting (bash's own read -n would block)
  stty -icanon min 0 time 0 </dev/tty 2>/dev/null
  dd bs=4096 count=1 </dev/tty >/dev/null 2>&1
  stty "$old" </dev/tty 2>/dev/null
}

# ask <question> <letters>: reads an answer from the terminal (stdin is the
# script itself when piped from curl). Enter picks the first letter; only the
# last letter typed counts.
ask() {
  local ans
  while :; do
    printf '  %s%s%s ' "$BLD" "$1" "$RST"
    IFS= read -r ans </dev/tty || { ANSWER=${2:0:1}; return; }
    ans=$(printf '%s' "$ans" | tr -cd '[:alpha:]' | tr '[:upper:]' '[:lower:]')
    ans=${ans: -1}
    [ -z "$ans" ] && ans=${2:0:1}
    case "$2" in *"$ans"*) ANSWER=$ans; return ;; esac
  done
}

# default_device <output|input>: "<1 if built-in> <name>" of the default device.
default_device() {
  system_profiler -json SPAudioDataType 2>/dev/null | awk -F'" : "' -v key="\"coreaudio_default_audio_$1_device\" : \"spaudio_yes\"" '
    function flush() { if (def) { print (bi ? 1 : 0) " " name; found = 1 } }
    /"_name"/ { flush(); name = $2; sub(/",?$/, "", name); def = 0; bi = 0 }
    index($0, key) { def = 1 }
    /coreaudio_device_type_builtin/ { bi = 1 }
    END { if (!found) flush() }'
}

# require_builtin <output|input> <what>: waits until sound plays through (or
# is recorded from) the built-in hardware. Fails if the user skips.
require_builtin() {
  local dev
  while :; do
    dev=$(default_device "$1")
    [ -z "$dev" ] && return 0
    [ "${dev%% *}" = 1 ] && return 0
    printf '  %sThe %s is "%s", not the built-in %s.%s\n' "$YEL" "$1" "${dev#* }" "$2" "$RST"
    ask "Disconnect headphones, AirPods or iPhone, then press Enter (s = skip)." "ys"
    [ "$ANSWER" = s ] && return 1
  done
}

# media_access <vide|soun> <what> <Settings name>: makes sure Terminal may
# use the camera or microphone. macOS asks once; the answer sticks.
media_access() {
  local st
  st=$(osascript -l JavaScript -e "$CAPTURE_JS" status "$1" 2>/dev/null)
  if [ "$st" = 0 ]; then
    printf '  %smacOS will ask whether Terminal may use the %s: click Allow.%s\n' "$YEL" "$2" "$RST"
    st=$(osascript -l JavaScript -e "$CAPTURE_JS" auth "$1" 2>/dev/null)
  fi
  case "$st" in
    3) return 0 ;;
    -1) row na "$3 test" "No $2 found" ;;
    *) row na "$3 test" "Terminal may not use the $2" "Allow it in System Settings > Privacy & Security > $3, or use Photo Booth" ;;
  esac
  NOT_TESTED+=("$2")
  return 1
}

# Volume is raised only when it is muted or too low to hear, and put back by
# cleanup(). Same for the microphone input level.
raise_volume() {
  [ -n "$VOL_OLD" ] && return 0
  VOL_OLD=$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)
  MUTED_OLD=$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)
  if [ "$MUTED_OLD" = true ] || { is_int "$VOL_OLD" && [ "$VOL_OLD" -lt 40 ]; }; then
    is_int "$VOL_OLD" || VOL_OLD=50
    osascript -e 'set volume output volume 60' -e 'set volume output muted false' >/dev/null 2>&1
    VOL_CHANGED=1
    printf '  %sVolume raised to 60 %% for the tests, restored afterwards.%s\n' "$DIM" "$RST"
  fi
}

raise_input() {
  [ -n "$IN_OLD" ] && return 0
  IN_OLD=$(osascript -e 'input volume of (get volume settings)' 2>/dev/null)
  if is_int "$IN_OLD" && [ "$IN_OLD" -lt 30 ]; then
    osascript -e 'set volume input volume 70' >/dev/null 2>&1
    IN_CHANGED=1
  fi
}

cleanup() {
  if [ "$VOL_CHANGED" = 1 ]; then
    osascript -e "set volume output volume $VOL_OLD" >/dev/null 2>&1
    [ "$MUTED_OLD" = true ] && osascript -e 'set volume output muted true' >/dev/null 2>&1
    VOL_CHANGED=0
  fi
  if [ "$IN_CHANGED" = 1 ]; then
    osascript -e "set volume input volume $IN_OLD" >/dev/null 2>&1
    IN_CHANGED=0
  fi
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  TMP_DIR=""
}

test_display() {
  printf '\n  %sDisplay test%s: the screen turns white, black, red, green, blue and gray.\n' "$BLD" "$RST"
  printf '  Look for dots that stay black or bright, spots, stains, and uneven light\n'
  printf '  at the edges. Click or press any key for the next colour, Esc to stop.\n'
  while :; do
    ask "Press Enter to start (s = skip)." "ys"
    if [ "$ANSWER" = s ]; then NOT_TESTED+=("display"); row na "Display test" "Skipped"; return; fi
    osascript -l JavaScript -e "$DISPLAY_JS" >/dev/null 2>&1
    flush_tty
    ask "Dead pixels, spots or stains seen? [n = all clean / y = problems / r = repeat]" "nyr"
    [ "$ANSWER" = r ] || break
  done
  if [ "$ANSWER" = n ]; then
    row ok "Display test" "No defects seen"
  else
    row bad "Display test" "Defects seen" "Look again closely: one dead pixel is a flaw, stains or lines are a repair"
    deduct 15 "Display defects seen in the colour test"
  fi
}

test_camera() {
  printf '\n  %sCamera test%s: shows the live camera image for up to 30 seconds. Check it is\n' "$BLD" "$RST"
  printf '  sharp with natural colours, and that the green light next to the camera is on.\n'
  ask "Press Enter to start (s = skip)." "ys"
  if [ "$ANSWER" = s ]; then NOT_TESTED+=("camera"); row na "Camera test" "Skipped"; return; fi
  media_access vide camera Camera || return
  local res
  while :; do
    res=$(osascript -l JavaScript -e "$CAPTURE_JS" show 2>/dev/null)
    flush_tty
    if [ "$res" != ok ]; then NOT_TESTED+=("camera"); row na "Camera test" "Could not open the camera${res:+ ($res)}"; return; fi
    ask "Sharp image, natural colours, green light on? [y / n / r = repeat]" "ynr"
    [ "$ANSWER" = r ] || break
  done
  if [ "$ANSWER" = y ]; then row ok "Camera test" "Image and light OK"
  else row bad "Camera test" "Image or light faulty"; deduct 10 "Camera failed the live image test"; fi
}

test_speakers() {
  printf '\n  %sSpeaker test%s: plays chimes on the left, then the right speaker, then a\n' "$BLD" "$RST"
  printf '  rising tone on both. Listen for silence, crackling, buzzing or rattling.\n'
  if ! require_builtin output speakers; then NOT_TESTED+=("speakers"); row na "Speaker test" "Skipped"; return; fi
  raise_volume

  local side label
  for side in left right; do
    label=$(printf '%s' "$side" | tr '[:lower:]' '[:upper:]')
    while :; do
      ask "Press Enter to play the $label speaker (s = skip)." "ys"
      if [ "$ANSWER" = s ]; then NOT_TESTED+=("$side speaker"); row na "Speaker $side" "Skipped"; continue 2; fi
      if [ "$(osascript -l JavaScript -e "$AUDIO_JS" "$side" 2>/dev/null)" != ok ]; then
        row na "Speaker $side" "Could not play a sound"; continue 2
      fi
      ask "Heard it clearly, only from the $label side? [y / n / r = repeat]" "ynr"
      [ "$ANSWER" = r ] || break
    done
    if [ "$ANSWER" = y ]; then row ok "Speaker $side" "Works"
    else row bad "Speaker $side" "Silent, weak or wrong side"; deduct 10 "$label speaker failed the test"; fi
  done

  while :; do
    ask "Press Enter to play the rising tone on both speakers (s = skip)." "ys"
    if [ "$ANSWER" = s ]; then NOT_TESTED+=("speaker sound quality"); row na "Speaker quality" "Skipped"; break; fi
    osascript -l JavaScript -e "$AUDIO_JS" sweep >/dev/null 2>&1
    ask "Clean all the way, no crackling, buzzing or rattling? [y / n / r = repeat]" "ynr"
    [ "$ANSWER" = r ] && continue
    if [ "$ANSWER" = y ]; then row ok "Speaker quality" "Clean"
    else row bad "Speaker quality" "Crackling, buzzing or rattling"; deduct 10 "Speakers distort in the sweep test"; fi
    break
  done
}

test_microphone() {
  printf '\n  %sMicrophone test%s: records 4 seconds while you talk, then plays it back.\n' "$BLD" "$RST"
  if ! require_builtin input microphone; then NOT_TESTED+=("microphone"); row na "Microphone test" "Skipped"; return; fi
  ask "Press Enter to start (s = skip)." "ys"
  if [ "$ANSWER" = s ]; then NOT_TESTED+=("microphone"); row na "Microphone test" "Skipped"; return; fi
  media_access soun microphone Microphone || return
  raise_volume
  raise_input
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mac-check.XXXXXX") || { NOT_TESTED+=("microphone"); row na "Microphone test" "No temp folder"; return; }

  local res peak db
  while :; do
    printf '  %sRecording for 4 seconds: talk now...%s\n' "$BLD" "$RST"
    res=$(osascript -l JavaScript -e "$AUDIO_JS" record "$TMP_DIR/mic.wav" 2>/dev/null)
    case "$res" in
      "ok "*) peak=${res#ok } ;;
      *) NOT_TESTED+=("microphone"); row na "Microphone test" "Could not record"; return ;;
    esac
    printf '  Playing it back...\n'
    osascript -l JavaScript -e "$AUDIO_JS" play "$TMP_DIR/mic.wav" >/dev/null 2>&1
    ask "Heard yourself clearly? [y / n / r = record again]" "ynr"
    [ "$ANSWER" = r ] || break
  done
  rm -f "$TMP_DIR/mic.wav"

  # Peak level in dBFS: talking near the Mac gives about -25 to 0, a dead
  # microphone stays at -60 or lower.
  db=${peak#-}
  local dead=0
  if ! is_int "$db"; then
    row na "Microphone level" "Not measured"
  elif [ "$peak" != "$db" ] && [ "$db" -ge 60 ]; then
    row bad "Microphone level" "No sound picked up (peak $peak dB)"
    deduct 15 "Microphone picked up no sound"; dead=1
  elif [ "$peak" != "$db" ] && [ "$db" -ge 35 ]; then
    row warn "Microphone level" "Very quiet (peak $peak dB)" "Talk closer to the Mac and record again"
  else
    row ok "Microphone level" "Picked up sound (peak $peak dB)"
  fi
  if [ "$ANSWER" = y ]; then row ok "Microphone playback" "Clear"
  else
    row bad "Microphone playback" "Unclear or silent"
    [ "$dead" = 1 ] || deduct 10 "Microphone recording unclear"
  fi
}

run_tests() {
  section "HANDS-ON TESTS"
  local all="display camera speakers microphone"
  if [ "$QUICK" = 1 ]; then
    NOT_TESTED+=($all); row na "Hands-on tests" "Skipped (--quick)"; return
  fi
  if ! have_tty; then
    NOT_TESTED+=($all); row na "Hands-on tests" "Skipped (no terminal to answer in)"; return
  fi
  ask "Run the hands-on tests now: screen, camera, speakers, microphone (about 2 minutes)? [Y/n]" "yn"
  if [ "$ANSWER" = n ]; then
    NOT_TESTED+=($all); row na "Hands-on tests" "Skipped"; return
  fi
  test_display
  test_camera
  test_speakers
  test_microphone
  cleanup
}

# ---------- result ----------

tested() { case " ${NOT_TESTED[*]} " in *" $1 "*) return 1 ;; *) return 0 ;; esac; }

summary() {
  [ "$SCORE" -lt 0 ] && SCORE=0
  local grade gcol verdict vcol filled bar=""
  if   [ "$SCORE" -ge 90 ]; then grade="Excellent"; gcol=$GRN
  elif [ "$SCORE" -ge 75 ]; then grade="Good";      gcol=$GRN
  elif [ "$SCORE" -ge 60 ]; then grade="Fair";      gcol=$YEL
  elif [ "$SCORE" -ge 40 ]; then grade="Poor";      gcol=$RED
  else                           grade="Bad";       gcol=$RED; fi

  if [ "${#BLOCKERS[@]}" -gt 0 ]; then
    verdict="DO NOT BUY (yet): resolve the blockers first"; vcol=$RED
  elif [ "$SCORE" -ge 75 ]; then
    verdict="Looks healthy: OK to buy after the checks below"; vcol=$GRN
  elif [ "$SCORE" -ge 60 ]; then
    verdict="Usable, but only at a clear discount"; vcol=$YEL
  else
    verdict="Not recommended"; vcol=$RED
  fi

  filled=$((SCORE / 5))
  local i=0; while [ $i -lt 20 ]; do
    if [ $i -lt $filled ]; then bar="$bar#"; else bar="$bar."; fi; i=$((i + 1))
  done

  local line="================================================================"
  printf '\n%s%s%s\n' "$BLD" "$line" "$RST"
  printf ' %sRESULT%s  %s%s%s\n' "$BLD" "$RST" "$PRODUCT" "${RAM:+, $RAM}" "${DISK_GB:+, $DISK_GB GB}"
  printf '%s\n' "${line//=/-}"
  printf ' %-14s %s%s%3d / 100%s  [%s]  %s%s%s\n' "Health score" "$BLD" "$gcol" "$SCORE" "$RST" "$bar" "$gcol" "$grade" "$RST"
  printf ' %-14s %s%s%s%s\n' "Verdict" "$BLD" "$vcol" "$verdict" "$RST"

  local x first
  if [ "${#BLOCKERS[@]}" -gt 0 ]; then
    first=1; for x in "${BLOCKERS[@]}"; do
      [ $first = 1 ] && printf ' %-14s' "Blockers" || printf ' %-14s' ""
      printf ' %sx %s%s\n' "$RED" "$x" "$RST"; first=0
    done
  fi
  if [ "${#DEDUCTIONS[@]}" -gt 0 ]; then
    first=1; for x in "${DEDUCTIONS[@]}"; do
      [ $first = 1 ] && printf ' %-14s' "Deductions" || printf ' %-14s' ""
      printf ' - %s\n' "$x"; first=0
    done
  else
    printf ' %-14s %s\n' "Deductions" "None"
  fi
  if [ "${#NOT_TESTED[@]}" -gt 0 ]; then
    local list; list=$(printf '%s, ' "${NOT_TESTED[@]}"); list=${list%, }
    printf ' %-14s %s%s%s\n' "Not tested" "$YEL" "$list" "$RST"
  fi
  [ -n "$OUTLOOK" ] && printf ' %-14s %s\n' "Rough outlook" "$OUTLOOK"
  printf '%s%s%s\n' "$BLD" "$line" "$RST"

  printf '\n%sStill check by hand (a script cannot):%s\n' "$BLD" "$RST"
  local n=0
  item() { n=$((n + 1)); printf '  %d. %s\n' "$n" "$1"; shift; for x in "$@"; do printf '     %s\n' "$x"; done; }
  tested display || item "Screen: full-screen white, black, red, green, blue. Look for dead" \
    "pixels, stains, coating damage and bright spots at the edges."
  item "Keyboard: press every key in TextEdit, check backlight and Touch ID." \
    "Trackpad: click in all corners, force click, two-finger scroll."
  item "Ports: charge from every port, plug a USB stick into each one."
  local media=""
  tested camera || media="camera"
  tested microphone || media="${media:+$media and }microphone"
  [ -n "$media" ] && item "$(printf '%s' "${media:0:1}" | tr '[:lower:]' '[:upper:]')${media:1}: record a short clip in Photo Booth and play it back."
  tested speakers || item "Speakers: play music and listen to both sides for crackling."
  item "Wi-Fi: join your phone's hotspot. Bluetooth: pair your headphones."
  item "At handover: seller signs out of their Apple Account, re-run this" \
    "check (Activation Lock must say \"Disabled\"), then seller runs" \
    "System Settings > General > Transfer or Reset > Erase All Content" \
    "and Settings while you watch."
  printf '\n%smac-check %s. Nothing was installed or sent anywhere.%s\n\n' "$DIM" "$VERSION" "$RST"
}

main() {
  USE_COLOR=1; QUICK=0
  [ -t 1 ] || USE_COLOR=0
  local arg
  for arg in "$@"; do
    case "$arg" in
      --quick) QUICK=1 ;;
      --no-color) USE_COLOR=0 ;;
      -h|--help) usage; return 0 ;;
      -v|--version) echo "mac-check $VERSION"; return 0 ;;
      *) echo "Unknown option: $arg" >&2; usage >&2; return 2 ;;
    esac
  done
  if [ "$(uname -s)" != Darwin ]; then echo "mac-check only runs on macOS." >&2; return 1; fi
  # sysctl reports arm64 hardware even when the shell runs under Rosetta
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != 1 ]; then
    echo "mac-check is made for Apple silicon Macs (M1 and later). This Mac has an Intel processor." >&2
    return 1
  fi

  setup_colors
  SCORE=100; BLOCKERS=(); DEDUCTIONS=(); NOT_TESTED=(); OUTLOOK=""; BAT_PTS=0
  VOL_OLD=""; VOL_CHANGED=0; IN_OLD=""; IN_CHANGED=0; TMP_DIR=""
  # Put the volume back and delete the recording even on Ctrl-C
  trap cleanup EXIT

  printf '\n%smac-check %s%s  used-Mac health check, %s\n' "$BLD" "$VERSION" "$RST" "$(date '+%Y-%m-%d %H:%M')"
  collect
  check_identity
  check_locks
  check_battery
  check_storage
  check_hardware
  check_stability
  run_tests
  summary
}

main "$@"
