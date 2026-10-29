#!/usr/bin/env bash

VERSION="2.0.0"
REPO_URL="https://github.com/cray06/driver_fix"
RAW_URL="https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh"

ROOT=${DRIVER_FIX_ROOT:-}
CONF_PREFIX="$ROOT/etc/modprobe.d/driver-fix"
STATE_DIR="$ROOT/var/lib/driver-fix"
GRUB_FILE="$ROOT/etc/default/grub"
GRUB_BACKUP="$GRUB_FILE.driver-fix.bak"

OPT_DIAGNOSE=0 OPT_DRY_RUN=0 OPT_YES=1 OPT_NO_COLOR=0 OPT_UNDO=0 OPT_PRIME=""

FAMILY="" DISTRO_NAME="" DISTRO_ID="" DISTRO_VERSION="" RUNNING_KERNEL="" NEWEST_KERNEL=""
KERNELS=() MISSING_KERNELS=() WRONG_KERNELS=()
declare -A KMOD_FLAVOR=() KMOD_FILE=() KMOD_VERSION=() KMOD_SIGNER=()
GPU_LINES=() CONNECTOR_LINES=() HAS_NVIDIA=0 HAS_OTHER_GPU=0 NV_DEVICE_ID="" NV_PCI_ADDR=""
NV_TURING=0 NV_RECENT=0
NV_LOADED=0 NV_LOADED_FLAVOR="" NOUVEAU_LOADED=0 NV_DRIVER_VERSION="" MODESET=""
NV_SMI_STATE="absent" NV_SMI_OK=0 NV_SMI_MSG="" NV_MISMATCH=0
NV_OPEN_REQUIRED=0 NV_OPEN_REQUIRED_SRC="" NV_RMINIT_FAIL=0 NV_RMINIT_CODE=""
NV_GSP_FAIL=0 NV_FW_MISSING=0 NV_FALLEN_BUS=0 KEY_REJECTED=0
SECURE_BOOT="off" PRIME_MODE="" DPKG_BROKEN=0 BOOT_FREE_KB=""
NV_PKGS=() DRIVER_PKGS=() WRONG_FLAVOR_PKGS=() DKMS_LINES=() APT_REMOVALS=()
WANT_FLAVOR="any"
BOOT_ID="" LAST_RUN_BOOT="" LAST_RUN_DATE="" REBOOTED_SINCE_FIX=0
PROBLEMS=() WARNINGS=() ADVICE=()

BRANCH="" PICK_SOURCE="" SWITCH_FROM="" USED_DKMS=0 MOK_PENDING=0 MOK_PASSWORD="" GRUB_PINNED=""
REBOOT_NEEDED=0 GPU_WORKING_NOW=0
DONE_COUNT=0 FAILED=()
STEP=0 TOTAL_STEPS=5
HAS_TTY=0 FANCY=0 LOG_FILE=/dev/null

NV_PKG_RE='^(nvidia-|libnvidia-|linux-(modules|objects|signatures)-nvidia-|xserver-xorg-video-nvidia-|libxnvctrl|screen-resolution-extra)'

setup_colors() {
  if [[ -t 1 && -z ${NO_COLOR:-} && $OPT_NO_COLOR -eq 0 ]]; then
    R=$'\e[0m' B=$'\e[1m' D=$'\e[2m'
    RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m'
    G1=$'\e[38;5;51m' G2=$'\e[38;5;45m' G3=$'\e[38;5;39m'
    FANCY=1
  else
    R='' B='' D='' RED='' GRN='' YLW='' BLU='' MAG='' CYN='' G1='' G2='' G3=''
    FANCY=0
  fi
}

repeat() { local s='' i; for ((i = 0; i < $2; i++)); do s+=$1; done; printf '%s' "$s"; }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }
log() { printf '%s\n' "$*" >>"$LOG_FILE" 2>/dev/null; }

ok()   { printf '  %s✔%s %s\n' "$GRN" "$R" "$*"; log "[ok] $*"; }
warn() { printf '  %s⚠%s %s\n' "$YLW" "$R" "$*"; log "[warn] $*"; }
fail() { printf '  %s✖%s %s\n' "$RED" "$R" "$*"; log "[fail] $*"; }
info() { printf '  %s➜%s %s\n' "$CYN" "$R" "$*"; }
note() { printf '    %s%s%s\n' "$D" "$*" "$R"; }
kv()   { printf '  %s%-16s%s %s\n' "$D" "$1" "$R" "$2"; }

banner() {
  printf '\n'
  printf '  %s░█▀▄░█▀▄░▀█▀░█░█░█▀▀░█▀▄░░░█▀▀░▀█▀░█░█%s\n' "$G1" "$R"
  printf '  %s░█░█░█▀▄░░█░░▀▄▀░█▀▀░█▀▄░░░█▀▀░░█░░▄▀▄%s\n' "$G2" "$R"
  printf '  %s░▀▀░░▀░▀░▀▀▀░░▀░░▀▀▀░▀░▀░░░▀░░░▀▀▀░▀░▀%s\n' "$G3" "$R"
  printf '  %sRéparation HDMI / écran externe · NVIDIA · v%s%s\n' "$D" "$VERSION" "$R"
}

step() {
  STEP=$((STEP + 1))
  local title="$STEP/$TOTAL_STEPS · $1"
  printf '\n  %s%s━━ %s %s%s\n' "$B" "$BLU" "$title" "$(repeat '━' $((50 - ${#title})))" "$R"
  log "== $title"
}

box() {
  local color=$1 line plain w=0
  shift
  for line in "$@"; do
    plain=$(strip_ansi "$line")
    ((${#plain} > w)) && w=${#plain}
  done
  printf '\n  %s╭%s╮%s\n' "$color" "$(repeat '─' $((w + 4)))" "$R"
  for line in "$@"; do
    plain=$(strip_ansi "$line")
    printf '  %s│%s  %s%*s  %s│%s\n' "$color" "$R" "$line" $((w - ${#plain})) '' "$color" "$R"
  done
  printf '  %s╰%s╯%s\n' "$color" "$(repeat '─' $((w + 4)))" "$R"
}

ask() {
  local question=$1 def=${2:-n} hint ans
  ((OPT_YES)) && { log "[ask] $question -> oui (automatique)"; return 0; }
  if ((!HAS_TTY)); then log "[ask] $question -> défaut $def (pas de terminal)"; [[ $def == o ]]; return; fi
  [[ $def == o ]] && hint="[O/n]" || hint="[o/N]"
  printf '\n  %s?%s %s%s%s %s%s%s ' "$BLU" "$R" "$B" "$question" "$R" "$D" "$hint" "$R"
  read -r ans </dev/tty || ans=""
  ans=${ans,,}
  [[ -z $ans ]] && ans=$def
  log "[ask] $question -> $ans"
  [[ $ans == o* || $ans == y* ]]
}

run() {
  local msg=$1
  shift
  if ((OPT_DRY_RUN)); then
    local cmd="$*"
    printf '  %s○%s %s %s(simulation : %s)%s\n' "$D" "$R" "$msg" "$D" "${cmd%%$'\n'*}" "$R"
    return 0
  fi
  printf '\n$ %s\n' "$*" >>"$LOG_FILE"
  "$@" </dev/null >>"$LOG_FILE" 2>&1 &
  local pid=$! i=0
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  if ((FANCY)); then
    printf '\e[?25l'
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s %s' "$CYN" "${frames[i++ % 10]}" "$R" "$msg"
      sleep 0.1
    done
  fi
  wait "$pid"
  local rc=$?
  ((FANCY)) && printf '\r\e[K\e[?25h'
  printf '[rc=%s]\n' "$rc" >>"$LOG_FILE"
  if ((rc == 0)); then
    ok "$msg"
    DONE_COUNT=$((DONE_COUNT + 1))
  else
    fail "$msg ${D}(erreur $rc)${R}"
    tail -n 4 "$LOG_FILE" | while IFS= read -r l; do note "${l:0:90}"; done
    FAILED+=("$msg")
  fi
  return "$rc"
}

write_file() {
  mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" >"$1.tmp.$$" && mv -f "$1.tmp.$$" "$1"
}

history_add() {
  ((OPT_DRY_RUN)) && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null && printf '%s  %s\n' "$(date '+%F %T')" "$*" >>"$STATE_DIR/history.log"
}

detect_distro() {
  local ID="" ID_LIKE="" PRETTY_NAME="" VERSION_ID="" key val
  if [[ -r $ROOT/etc/os-release ]]; then
    while IFS='=' read -r key val; do
      val=${val%\"} val=${val#\"} val=${val%\'} val=${val#\'}
      case $key in
        ID) ID=$val ;;
        ID_LIKE) ID_LIKE=$val ;;
        PRETTY_NAME) PRETTY_NAME=$val ;;
        VERSION_ID) VERSION_ID=$val ;;
      esac
    done <"$ROOT/etc/os-release"
  fi
  DISTRO_NAME=${PRETTY_NAME:-${ID:-inconnue}}
  DISTRO_ID=${ID:-inconnue}
  DISTRO_VERSION=${VERSION_ID:-}
  local ids=" ${ID:-} ${ID_LIKE:-} "
  case "$ids" in
    *" manjaro "*) FAMILY=manjaro ;;
    *" ubuntu "*) FAMILY=ubuntu ;;
    *" debian "*) FAMILY=debian ;;
    *" fedora "*) FAMILY=fedora ;;
    *" arch "*) FAMILY=arch ;;
    *) FAMILY=unknown ;;
  esac
}

list_kernels() {
  local d k
  for d in "$ROOT"/lib/modules/*/; do
    [[ -d $d ]] || continue
    k=$(basename "$d")
    [[ -e $ROOT/boot/vmlinuz-$k || -e $ROOT/lib/modules/$k/vmlinuz ]] && printf '%s\n' "$k"
  done | sort -V
}

nv_mod_flavor() {
  local lic
  lic=$(modinfo -k "$1" -F license nvidia 2>/dev/null | head -n1)
  case $lic in
    "") echo none ;;
    *MIT* | *GPL*) echo open ;;
    *) echo proprietary ;;
  esac
}

refresh_kernel() {
  local k=$1
  KMOD_FLAVOR[$k]=$(nv_mod_flavor "$k")
  KMOD_FILE[$k]=$(modinfo -k "$k" -F filename nvidia 2>/dev/null | head -n1)
  KMOD_VERSION[$k]=$(modinfo -k "$k" -F version nvidia 2>/dev/null | head -n1)
  KMOD_SIGNER[$k]=$(modinfo -k "$k" -F signer nvidia 2>/dev/null | head -n1)
}

has_nv_module() { [[ $(nv_mod_flavor "$1") != none ]]; }

module_ok() {
  local f=${KMOD_FLAVOR[$1]:-}
  [[ -z $f ]] && f=$(nv_mod_flavor "$1")
  [[ $f != none ]] && [[ $WANT_FLAVOR == any || $f == "$WANT_FLAVOR" ]]
}

detect_kernels() {
  RUNNING_KERNEL=$(uname -r)
  mapfile -t KERNELS < <(list_kernels)
  ((${#KERNELS[@]} == 0)) && KERNELS=("$RUNNING_KERNEL")
  NEWEST_KERNEL=${KERNELS[-1]}
  local k
  for k in "${KERNELS[@]}"; do refresh_kernel "$k"; done
  classify_kernels
}

classify_kernels() {
  MISSING_KERNELS=() WRONG_KERNELS=()
  local k
  for k in "${KERNELS[@]}"; do
    case ${KMOD_FLAVOR[$k]:-none} in
      none) MISSING_KERNELS+=("$k") ;;
      *) module_ok "$k" || WRONG_KERNELS+=("$k") ;;
    esac
  done
}

detect_gpus() {
  local d class vendor device name drv
  GPU_LINES=() HAS_NVIDIA=0 HAS_OTHER_GPU=0
  for d in "$ROOT"/sys/bus/pci/devices/*; do
    [[ -r $d/class ]] || continue
    class=$(<"$d/class")
    [[ $class == 0x03* ]] || continue
    vendor=$(<"$d/vendor")
    device=$(<"$d/device")
    name=$(lspci -s "${d##*/}" 2>/dev/null | cut -d: -f3- | sed -E 's/^ +//; s/ \(rev [0-9a-f]+\)$//')
    drv=$(basename "$(readlink "$d/driver" 2>/dev/null)" 2>/dev/null)
    case $vendor in
      0x10de)
        HAS_NVIDIA=1
        NV_DEVICE_ID=${device#0x}
        NV_PCI_ADDR=${d##*/}
        ((16#$NV_DEVICE_ID >= 16#1e00)) && NV_TURING=1
        ((16#$NV_DEVICE_ID >= 16#2900)) && NV_RECENT=1
        [[ -z $name ]] && name="NVIDIA [10de:$NV_DEVICE_ID]"
        ;;
      0x1002) HAS_OTHER_GPU=1; [[ -z $name ]] && name="AMD [1002:${device#0x}]" ;;
      0x8086) HAS_OTHER_GPU=1; [[ -z $name ]] && name="Intel [8086:${device#0x}]" ;;
      *) HAS_OTHER_GPU=1; [[ -z $name ]] && name="GPU [${vendor#0x}:${device#0x}]" ;;
    esac
    GPU_LINES+=("$name|${drv:-aucun pilote}|${d##*/}")
  done
}

detect_connectors() {
  CONNECTOR_LINES=()
  local c name card drv st
  for c in "$ROOT"/sys/class/drm/card*-*; do
    [[ -r $c/status ]] || continue
    name=${c##*/}
    [[ $name == *eDP* || $name == *LVDS* ]] && continue
    card=${name%%-*}
    drv=$(basename "$(readlink "$ROOT/sys/class/drm/$card/device/driver" 2>/dev/null)" 2>/dev/null)
    st=$(<"$c/status")
    CONNECTOR_LINES+=("${name#*-}|${drv:-?}|$st")
  done
}

detect_secure_boot() {
  SECURE_BOOT="off"
  if [[ ! -d $ROOT/sys/firmware/efi ]]; then SECURE_BOOT="legacy"; return; fi
  if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled' && SECURE_BOOT="on"
    return
  fi
  local f
  for f in "$ROOT"/sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r $f ]] && [[ $(od -An -t u1 -j4 -N1 "$f" | tr -d ' ') == 1 ]] && SECURE_BOOT="on"
  done
}

kernel_log() {
  journalctl -k -b 0 --no-pager 2>/dev/null || dmesg 2>/dev/null
}

detect_driver_state() {
  local m=$ROOT/sys/module
  [[ -d $m/nvidia ]] && NV_LOADED=1
  [[ -d $m/nouveau ]] && NOUVEAU_LOADED=1
  [[ -r $m/nvidia_drm/parameters/modeset ]] && MODESET=$(<"$m/nvidia_drm/parameters/modeset")
  [[ -r $m/nvidia/version ]] && NV_DRIVER_VERSION=$(<"$m/nvidia/version")

  if ((NV_LOADED)); then
    local pv=$ROOT/proc/driver/nvidia/version
    if [[ -r $pv ]]; then
      grep -qi 'open kernel module' "$pv" && NV_LOADED_FLAVOR=open || NV_LOADED_FLAVOR=proprietary
    elif [[ -r $m/nvidia/taint ]]; then
      [[ $(<"$m/nvidia/taint") == *P* ]] && NV_LOADED_FLAVOR=proprietary || NV_LOADED_FLAVOR=open
    else
      NV_LOADED_FLAVOR=unknown
    fi
  fi

  probe_nvidia_smi

  local full klog
  full=$(kernel_log)
  klog=$(grep -Ei 'nvidia|nvrm' <<<"$full")
  {
    printf -- '--- journal noyau (NVIDIA, 40 dernières lignes) ---\n'
    tail -n 40 <<<"$klog"
  } >>"$LOG_FILE" 2>/dev/null
  grep -Eqi 'key was rejected|unavailable key is rejected|required key not available|unsigned module loading is restricted' <<<"$full" && KEY_REJECTED=1
  grep -qi 'API mismatch' <<<"$klog" && NV_MISMATCH=1
  if grep -qi 'requires use of the NVIDIA open kernel modules' <<<"$klog"; then
    NV_OPEN_REQUIRED=1 NV_OPEN_REQUIRED_SRC=log
  fi
  if grep -qi 'RmInitAdapter failed' <<<"$klog"; then
    NV_RMINIT_FAIL=1
    NV_RMINIT_CODE=$(grep -oiE 'RmInitAdapter failed! \([^)]*\)' <<<"$klog" | head -n1 | grep -oE '\(.*\)')
  fi
  grep -Eqi 'gsp[^ ]* .*(fail|error|timeout)|(fail|error|unable)[^ ]* .*gsp' <<<"$klog" && NV_GSP_FAIL=1
  grep -Eqi 'firmware load for nvidia/.* failed|failed to load .*firmware' <<<"$klog" && NV_FW_MISSING=1
  grep -qi 'fallen off the bus' <<<"$klog" && NV_FALLEN_BUS=1

  command -v prime-select &>/dev/null && PRIME_MODE=$(prime-select query 2>/dev/null)
  if [[ $FAMILY == ubuntu || $FAMILY == debian ]] && command -v dpkg &>/dev/null; then
    [[ -n $(dpkg --audit 2>/dev/null) ]] && DPKG_BROKEN=1
  fi
  if [[ -d $ROOT/boot ]]; then
    BOOT_FREE_KB=$(df -Pk "$ROOT/boot" 2>/dev/null | awk 'NR == 2 {print $4}')
  fi
}

probe_nvidia_smi() {
  NV_SMI_OK=0 NV_SMI_MSG=""
  if ! command -v nvidia-smi &>/dev/null; then NV_SMI_STATE=absent; return; fi
  local out rc
  out=$(timeout 15 nvidia-smi -L 2>&1)
  rc=$?
  NV_SMI_MSG=$(head -n1 <<<"$out")
  log "nvidia-smi -L (rc=$rc) : $out"
  if ((rc == 0)) && grep -q '^GPU ' <<<"$out"; then
    NV_SMI_STATE=ok NV_SMI_OK=1
  elif grep -qi 'no devices were found' <<<"$out"; then
    NV_SMI_STATE=nodev
  else
    NV_SMI_STATE=fail
  fi
  grep -qi 'version mismatch' <<<"$out" && NV_MISMATCH=1
}

dpkg_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' "$@" 2>/dev/null | awk -F'|' '$1 ~ /^ii/ {print $2}'
}

pkg_flavor() { [[ $1 == *-open || $1 == *-open-* ]] && echo open || echo proprietary; }

detect_packages() {
  NV_PKGS=() DRIVER_PKGS=() DKMS_LINES=()
  if command -v dpkg-query &>/dev/null; then
    mapfile -t NV_PKGS < <(dpkg_installed 'nvidia-driver-*' 'linux-modules-nvidia-*' 'linux-objects-nvidia-*' \
      'linux-signatures-nvidia-*' 'nvidia-dkms-*' 'nvidia-kernel-source-*' 'nvidia-utils-*' 'nvidia-firmware-*' | sort -u)
    mapfile -t DRIVER_PKGS < <(printf '%s\n' "${NV_PKGS[@]}" | grep -E '^nvidia-driver-[0-9]+(-server)?(-open)?$' | sort -V)
  fi
  command -v dkms &>/dev/null && mapfile -t DKMS_LINES < <(dkms status nvidia 2>/dev/null)
  log "Paquets NVIDIA : ${NV_PKGS[*]:-aucun}"
  log "DKMS : ${DKMS_LINES[*]:-rien}"
}

find_wrong_flavor_pkgs() {
  WRONG_FLAVOR_PKGS=()
  [[ $WANT_FLAVOR == any ]] && return 0
  local p
  for p in "${NV_PKGS[@]}"; do
    [[ $p =~ ^(linux-(modules|objects|signatures)-nvidia|nvidia-dkms|nvidia-kernel-source)-[0-9]+ ]] || continue
    [[ $(pkg_flavor "$p") == "$WANT_FLAVOR" ]] || WRONG_FLAVOR_PKGS+=("$p")
  done
}

detect_last_run() {
  [[ -r $ROOT/proc/sys/kernel/random/boot_id ]] && BOOT_ID=$(<"$ROOT/proc/sys/kernel/random/boot_id")
  local f=$STATE_DIR/last-run key val
  [[ -r $f ]] || return 0
  while IFS='=' read -r key val; do
    case $key in
      boot_id) LAST_RUN_BOOT=$val ;;
      date) LAST_RUN_DATE=$val ;;
    esac
  done <"$f"
  [[ -n $BOOT_ID && -n $LAST_RUN_BOOT && $BOOT_ID != "$LAST_RUN_BOOT" ]] && REBOOTED_SINCE_FIX=1
  return 0
}

save_last_run() {
  ((OPT_DRY_RUN)) && return 0
  write_file "$STATE_DIR/last-run" "boot_id=$BOOT_ID
date=$(date '+%F %T')
branch=$BRANCH
reboot_needed=$REBOOT_NEEDED" 2>/dev/null
}

decide_flavor() {
  WANT_FLAVOR=any
  if ((NV_OPEN_REQUIRED)); then
    WANT_FLAVOR=open
  elif ((NV_RECENT)); then
    WANT_FLAVOR=open NV_OPEN_REQUIRED=1 NV_OPEN_REQUIRED_SRC=pci
  fi
  classify_kernels
  find_wrong_flavor_pkgs
}

nv_installed() {
  ((${#MISSING_KERNELS[@]} < ${#KERNELS[@]})) || command -v nvidia-smi &>/dev/null || ((${#DRIVER_PKGS[@]}))
}

flavor_label() {
  case $1 in
    open) echo "open (Dual MIT/GPL)" ;;
    proprietary) echo "propriétaire" ;;
    none) echo "absent" ;;
    *) echo "inconnue" ;;
  esac
}

analyze() {
  PROBLEMS=() WARNINGS=() ADVICE=()
  local k p
  ((DPKG_BROKEN)) && PROBLEMS+=("Des paquets sont à moitié installés (apt/dpkg interrompu)")
  if [[ -n $BOOT_FREE_KB ]] && ((BOOT_FREE_KB < 150000)); then
    WARNINGS+=("Peu d'espace libre dans /boot ($((BOOT_FREE_KB / 1024)) Mo) : l'initramfs peut échouer")
    ADVICE+=("Libère /boot : sudo apt autoremove --purge (retire les vieux noyaux)")
  fi

  local open_in_place=0
  [[ $NV_LOADED_FLAVOR == open && ${KMOD_FLAVOR[$RUNNING_KERNEL]:-} == open ]] && open_in_place=1
  if ((NV_OPEN_REQUIRED && !open_in_place)); then
    if [[ $NV_OPEN_REQUIRED_SRC == log ]]; then
      WARNINGS+=("Le noyau indique que ce GPU exige les modules NVIDIA open (confirmé par les logs)")
    else
      WARNINGS+=("GPU récent (10de:$NV_DEVICE_ID) : les modules NVIDIA open sont requis (déduit de l'ID PCI)")
    fi
  fi

  if ! nv_installed; then
    PROBLEMS+=("Aucun pilote NVIDIA n'est installé")
  else
    for k in "${MISSING_KERNELS[@]}"; do
      if [[ $k == "$RUNNING_KERNEL" ]]; then
        PROBLEMS+=("Pas de module NVIDIA pour le noyau actuel ($k)")
      elif [[ $k == "$NEWEST_KERNEL" ]]; then
        PROBLEMS+=("Pas de module NVIDIA pour le noyau du prochain démarrage ($k)")
      else
        WARNINGS+=("Pas de module NVIDIA pour l'ancien noyau $k (secours)")
      fi
    done
    for k in "${WRONG_KERNELS[@]}"; do
      PROBLEMS+=("Le module installé pour $k est $(flavor_label "${KMOD_FLAVOR[$k]}") alors que ce GPU exige les modules $WANT_FLAVOR")
    done
  fi

  if [[ $WANT_FLAVOR != any ]]; then
    for p in "${DRIVER_PKGS[@]}"; do
      [[ $(pkg_flavor "$p") == "$WANT_FLAVOR" ]] || PROBLEMS+=("Le paquet $p installe la variante propriétaire, incompatible avec ce GPU")
    done
    ((${#WRONG_FLAVOR_PKGS[@]})) && PROBLEMS+=("Modules noyau de la mauvaise variante encore installés : ${WRONG_FLAVOR_PKGS[*]}")
  fi
  ((${#DRIVER_PKGS[@]} > 1)) && WARNINGS+=("Plusieurs pilotes NVIDIA installés en même temps : ${DRIVER_PKGS[*]}")

  local disk=${KMOD_FLAVOR[$RUNNING_KERNEL]:-none}
  if ((NV_LOADED)) && [[ $NV_LOADED_FLAVOR == open || $NV_LOADED_FLAVOR == proprietary ]]; then
    if [[ $WANT_FLAVOR != any && $NV_LOADED_FLAVOR != "$WANT_FLAVOR" ]]; then
      if [[ $disk == "$WANT_FLAVOR" ]]; then
        PROBLEMS+=("Le module chargé en mémoire est $(flavor_label "$NV_LOADED_FLAVOR"), mais le bon module ($WANT_FLAVOR) est déjà sur le disque : il faut redémarrer")
        REBOOT_NEEDED=1
      else
        PROBLEMS+=("Le module chargé en mémoire est $(flavor_label "$NV_LOADED_FLAVOR") alors que ce GPU exige les modules $WANT_FLAVOR")
      fi
    elif [[ $disk != none && $NV_LOADED_FLAVOR != "$disk" ]]; then
      WARNINGS+=("Le module en mémoire ($NV_LOADED_FLAVOR) diffère de celui sur le disque ($disk) : redémarrage nécessaire")
      REBOOT_NEEDED=1
    fi
  fi

  if ((NV_RMINIT_FAIL)); then
    PROBLEMS+=("Le pilote est chargé mais n'arrive pas à initialiser le GPU (RmInitAdapter failed ${NV_RMINIT_CODE:-})")
    if ((NV_OPEN_REQUIRED)) && [[ $NV_LOADED_FLAVOR != open ]]; then
      ADVICE+=("Cause identifiée : module propriétaire chargé sur un GPU qui exige les modules open")
    else
      ADVICE+=("RmInitAdapter sans cause évidente : vérifie le firmware GSP, le mode graphique du BIOS (Hybrid / Discrete) et mets le BIOS à jour")
    fi
  fi
  ((NV_GSP_FAIL)) && PROBLEMS+=("Erreur du firmware GSP de la carte NVIDIA dans le journal noyau")
  local fwver=${KMOD_VERSION[$RUNNING_KERNEL]:-$NV_DRIVER_VERSION}
  if [[ $disk == open && -n $fwver ]] && ! compgen -G "$ROOT/lib/firmware/nvidia/$fwver/gsp_*" >/dev/null; then
    NV_FW_MISSING=1
  fi
  if ((NV_FW_MISSING)); then
    PROBLEMS+=("Firmware GSP NVIDIA introuvable${fwver:+ pour la version $fwver} (/lib/firmware/nvidia)")
    local drv="nvidia-driver-<version>"
    ((${#DRIVER_PKGS[@]})) && drv=${DRIVER_PKGS[-1]}
    ADVICE+=("Réinstalle le pilote pour récupérer le firmware : sudo apt-get install --reinstall $drv")
  fi
  if ((NV_FALLEN_BUS)); then
    PROBLEMS+=("La carte NVIDIA a « disparu du bus » (fallen off the bus) : souvent alimentation/BIOS, pas un problème de paquet")
    ADVICE+=("Mets à jour le BIOS et teste avec le paramètre noyau pcie_aspm=off ; le script ne peut pas corriger ça")
  fi

  case $NV_SMI_STATE in
    ok) ;;
    absent) nv_installed && WARNINGS+=("nvidia-smi est absent (paquet nvidia-utils manquant ?)") ;;
    nodev) ((NV_LOADED)) && PROBLEMS+=("nvidia-smi : « No devices were found » (le pilote ne gère pas le GPU)") ;;
    fail) ((NV_LOADED)) && PROBLEMS+=("nvidia-smi échoue : ${NV_SMI_MSG:-erreur inconnue}") ;;
  esac

  if ((KEY_REJECTED)); then
    PROBLEMS+=("Secure Boot refuse de charger le module NVIDIA (signature non reconnue)")
  fi
  if [[ $SECURE_BOOT == on && ${KMOD_FLAVOR[$RUNNING_KERNEL]:-none} != none && -z ${KMOD_SIGNER[$RUNNING_KERNEL]:-} ]]; then
    WARNINGS+=("Secure Boot activé et module NVIDIA de $RUNNING_KERNEL non signé : il sera refusé")
  fi
  ((NV_MISMATCH)) && PROBLEMS+=("Le pilote a été mis à jour sans redémarrer (version mismatch)")
  ((NOUVEAU_LOADED)) && PROBLEMS+=("Le pilote libre « nouveau » est utilisé à la place du pilote NVIDIA")
  if [[ $PRIME_MODE == intel ]]; then
    PROBLEMS+=("Mode PRIME « intel » : la carte NVIDIA est éteinte (le port HDMI est souvent relié à elle)")
  fi
  if ((NV_LOADED)) && [[ $MODESET == N ]]; then
    PROBLEMS+=("L'option nvidia-drm modeset est désactivée")
  fi
  if nv_installed && ((!NV_LOADED && !NOUVEAU_LOADED && !KEY_REJECTED)) && module_ok "$RUNNING_KERNEL"; then
    WARNINGS+=("Le module NVIDIA existe mais n'est pas chargé (un redémarrage est sûrement nécessaire)")
  fi
  if [[ $RUNNING_KERNEL != "$NEWEST_KERNEL" ]]; then
    WARNINGS+=("Le PC tourne sur $RUNNING_KERNEL alors que $NEWEST_KERNEL est installé (pas redémarré depuis une mise à jour ?)")
  fi
  if ((REBOOTED_SINCE_FIX && !NV_SMI_OK)); then
    WARNINGS+=("Le PC a redémarré depuis la dernière réparation (${LAST_RUN_DATE:-date inconnue}) et le GPU ne répond toujours pas")
    ADVICE+=("Joins /var/log/driver-fix.log et la sortie de --diagnose à une issue : $REPO_URL/issues")
  fi
}

configure_modprobe() {
  if ! module_ok "$NEWEST_KERNEL" && ! module_ok "$RUNNING_KERNEL"; then
    if ((OPT_DRY_RUN)); then
      note "« nouveau » serait désactivé seulement si le module NVIDIA s'installe correctement"
    else
      warn "Pas de module NVIDIA utilisable : « nouveau » reste actif (sinon risque d'écran noir)"
    fi
    return 0
  fi
  local f=$CONF_PREFIX-nouveau.conf c
  c="# Ajouté par driver-fix ($REPO_URL) — annuler : sudo bash fix.sh --undo
blacklist nouveau
options nouveau modeset=0"
  if [[ -r $f && $(<"$f") == "$c" ]]; then ok "« nouveau » déjà désactivé"; else
    run "Désactivation du pilote libre « nouveau »" write_file "$f" "$c" && history_add "écrit $f"
  fi
  f=$CONF_PREFIX-nvidia.conf
  c="# Ajouté par driver-fix ($REPO_URL) — annuler : sudo bash fix.sh --undo
options nvidia-drm modeset=1"
  if [[ -r $f && $(<"$f") == "$c" ]]; then ok "nvidia-drm modeset déjà activé"; else
    run "Activation de nvidia-drm modeset (nécessaire pour l'HDMI)" write_file "$f" "$c" && history_add "écrit $f"
  fi
}

fix_prime() {
  command -v prime-select &>/dev/null || return 0
  ((HAS_OTHER_GPU)) || return 0
  local target=$OPT_PRIME
  if [[ -z $target ]]; then
    [[ $PRIME_MODE == intel || -z $PRIME_MODE ]] && target="on-demand" || return 0
  fi
  [[ $target == "$PRIME_MODE" ]] && { ok "Mode PRIME déjà sur « $target »"; return 0; }
  run "Mode PRIME : ${PRIME_MODE:-?} → $target" prime-select "$target" &&
    history_add "prime-select ${PRIME_MODE:-?} -> $target (annuler : sudo prime-select ${PRIME_MODE:-on-demand})"
}

secure_boot_enroll() {
  [[ $SECURE_BOOT == on ]] || return 0
  refresh_kernel "$NEWEST_KERNEL"
  local signer=${KMOD_SIGNER[$NEWEST_KERNEL]:-} file=${KMOD_FILE[$NEWEST_KERNEL]:-}
  if ((!KEY_REJECTED && !USED_DKMS)) && [[ -n $signer && $file != */updates/dkms/* ]]; then
    ok "Secure Boot : module NVIDIA signé par « $signer »"
    return 0
  fi
  command -v mokutil &>/dev/null || {
    warn "mokutil absent : impossible d'enregistrer la clé Secure Boot (sudo apt install mokutil)"
    FAILED+=("Enregistrement de la clé Secure Boot")
    return 1
  }
  local key
  for key in "$ROOT/var/lib/shim-signed/mok/MOK.der" "$ROOT/var/lib/dkms/mok.pub" "$ROOT/etc/pki/akmods/certs/public_key.der"; do
    [[ -r $key ]] || continue
    if mokutil --test-key "$key" 2>&1 | grep -qi 'already enrolled'; then
      ok "Secure Boot : clé de signature déjà enregistrée"
      return 0
    fi
    if ((OPT_DRY_RUN)); then
      run "Enregistrement de la clé Secure Boot" mokutil --import "$key"
      return 0
    fi
    if mok_import "$key"; then
      MOK_PENDING=1
      ok "Clé Secure Boot prête à être enregistrée au redémarrage"
      history_add "mokutil --import $key"
    else
      fail "Échec de l'enregistrement de la clé Secure Boot"
      note "À faire à la main : sudo mokutil --import $key"
      FAILED+=("Enregistrement de la clé Secure Boot")
    fi
    return 0
  done
  warn "Secure Boot activé mais aucune clé de signature MOK trouvée"
  note "Sur Ubuntu, préfère les modules pré-compilés signés (linux-modules-nvidia-*)."
  note "Sinon : sudo update-secureboot-policy --new-key, puis relance ce script."
  FAILED+=("Signature du module pour Secure Boot")
}

mok_import() {
  local key=$1 pw hash
  pw=$(printf '%04d%04d' $((RANDOM % 10000)) $((RANDOM % 10000)))
  hash=$(mktemp) || return 1
  if mokutil --generate-hash="$pw" >"$hash" 2>>"$LOG_FILE" && [[ -s $hash ]] &&
    mokutil --import "$key" --hash-file "$hash" >>"$LOG_FILE" 2>&1; then
    rm -f "$hash"
    MOK_PASSWORD=$pw
    mkdir -p "$STATE_DIR" && (umask 077 && printf '%s\n' "$pw" >"$STATE_DIR/mok-password")
    return 0
  fi
  rm -f "$hash"
  ((HAS_TTY)) || return 1
  info "Choisis un mot de passe temporaire (8 caractères), à retaper au prochain démarrage :"
  mokutil --import "$key" </dev/tty
}

apt_install() { apt-get -o DPkg::Lock::Timeout=300 install -y "$@"; }
apt_remove() { apt-get -o DPkg::Lock::Timeout=300 remove -y "$@"; }
pkg_available() { apt-cache show "$1" &>/dev/null; }

apt_check_removals() {
  local action=$1 sim rm=() bad=() p
  shift
  sim=$(LC_ALL=C apt-get -s -o DPkg::Lock::Timeout=300 "$action" "$@" 2>&1)
  if [[ $? -ne 0 ]]; then
    fail "APT refuse l'opération « $action $* » (conflit de dépendances ?)"
    tail -n 5 <<<"$sim" | while IFS= read -r l; do note "${l:0:90}"; done
    log "$sim"
    return 1
  fi
  mapfile -t rm < <(awk '/^Remv /{print $2}' <<<"$sim")
  for p in "${rm[@]}"; do [[ $p =~ $NV_PKG_RE ]] || bad+=("$p"); done
  if ((${#bad[@]})); then
    fail "Opération annulée : APT voulait aussi retirer ${bad[*]}"
    note "Rien n'a été modifié. Règle ce conflit à la main (détails dans $LOG_FILE)."
    log "$sim"
    FAILED+=("$action $* (retrait non souhaité de ${bad[*]})")
    return 1
  fi
  APT_REMOVALS=("${rm[@]}")
  return 0
}

apt_safe_install() {
  local msg=$1
  shift
  APT_REMOVALS=()
  apt_check_removals install "$@" || return 1
  if ((${#APT_REMOVALS[@]})); then
    warn "Cette installation remplace : ${APT_REMOVALS[*]}"
    ask "Continuer ?" o || { info "Ignoré à ta demande."; FAILED+=("$msg (refusé)"); return 1; }
  fi
  run "$msg" apt_install "$@" || return 1
  history_add "apt install $* ${APT_REMOVALS[*]:+(a retiré : ${APT_REMOVALS[*]})}"
}

ubuntu_drivers_list() {
  command -v ubuntu-drivers &>/dev/null || return 0
  ubuntu-drivers devices 2>/dev/null | awk '$1 == "driver" && $3 ~ /^nvidia-driver-/ {
    print $3 ($0 ~ /recommended/ ? " recommended" : "") }'
}

ubuntu_pick_branch() {
  local pkg="" cand l list=() rec="" match=()
  SWITCH_FROM="" PICK_SOURCE=""

  for pkg in "${DRIVER_PKGS[@]}"; do
    [[ $WANT_FLAVOR == any || $(pkg_flavor "$pkg") == "$WANT_FLAVOR" ]] && match+=("$pkg")
  done
  if ((${#match[@]})); then
    pkg=${match[-1]}
    BRANCH=${pkg#nvidia-driver-} PICK_SOURCE=installed
    ok "Pilote déjà installé et adapté : ${B}$pkg${R}"
    return 0
  fi

  mapfile -t list < <(ubuntu_drivers_list)
  for l in "${list[@]}"; do [[ $l == *recommended ]] && rec=${l%% *}; done

  if ((${#DRIVER_PKGS[@]})); then
    cand="${DRIVER_PKGS[-1]}-open"
    if pkg_available "$cand"; then
      pkg=$cand SWITCH_FROM=${DRIVER_PKGS[-1]} PICK_SOURCE=same-branch
    fi
  fi

  if [[ -z $pkg && -n $rec ]]; then
    if [[ $WANT_FLAVOR == any || $(pkg_flavor "$rec") == "$WANT_FLAVOR" ]]; then
      pkg=$rec PICK_SOURCE=ubuntu-drivers
    else
      pkg=$(printf '%s\n' "${list[@]%% *}" | grep -E -- '-open$' | grep -v -- '-server' | sort -V | tail -n1)
      [[ -n $pkg ]] && PICK_SOURCE=ubuntu-drivers-open
    fi
  fi
  if [[ -z $pkg && ${#list[@]} -gt 0 && $WANT_FLAVOR == open ]]; then
    pkg=$(printf '%s\n' "${list[@]%% *}" | grep -E -- '-open$' | sort -V | tail -n1)
    [[ -n $pkg ]] && PICK_SOURCE=ubuntu-drivers-open
  fi

  if [[ -z $pkg ]]; then
    local suffix=''
    ((NV_TURING)) || [[ $WANT_FLAVOR == open ]] && suffix='-open'
    pkg=$(apt-cache pkgnames nvidia-driver- 2>/dev/null | grep -E "^nvidia-driver-[0-9]+$suffix\$" | sort -V |
      awk -v t="$NV_TURING" '{ split($0, a, "-"); if (t == 1 || a[3] + 0 <= 580) last = $0 } END { print last }')
    [[ -n $pkg ]] && PICK_SOURCE=apt
  fi

  if [[ -z $pkg ]] || ! pkg_available "$pkg"; then
    fail "Impossible de trouver un pilote NVIDIA ${WANT_FLAVOR/any/} adapté dans les dépôts"
    note "Vérifie que les dépôts « restricted » sont activés, puis : sudo ubuntu-drivers devices"
    FAILED+=("Choix du pilote NVIDIA")
    return 1
  fi
  ((${#DRIVER_PKGS[@]})) && [[ -z $SWITCH_FROM ]] && SWITCH_FROM=${DRIVER_PKGS[-1]}
  BRANCH=${pkg#nvidia-driver-}
  case $PICK_SOURCE in
    ubuntu-drivers*) ok "Pilote choisi par ubuntu-drivers pour ce GPU : ${B}$pkg${R}" ;;
    same-branch) ok "Même version, variante open : ${B}$pkg${R}" ;;
    apt) warn "Pilote choisi dans les dépôts sans vérification de l'ID PCI : ${B}$pkg${R}" ;;
  esac
  [[ -n $SWITCH_FROM ]] && info "Remplacement prévu : $SWITCH_FROM → $pkg"
  return 0
}

ubuntu_remove_wrong_flavor() {
  detect_packages
  find_wrong_flavor_pkgs
  ((${#WRONG_FLAVOR_PKGS[@]})) || return 0
  warn "Ces paquets fournissent des modules propriétaires incompatibles : ${WRONG_FLAVOR_PKGS[*]}"
  note "Ils seront désinstallés (pas de purge). Pour revenir en arrière : sudo apt-get install ${WRONG_FLAVOR_PKGS[*]}"
  APT_REMOVALS=()
  apt_check_removals remove "${WRONG_FLAVOR_PKGS[@]}" || return 1
  ask "Désinstaller ces paquets ?" o || { warn "Conservés : le mauvais module risque d'être chargé au démarrage"; return 1; }
  run "Retrait des modules propriétaires incompatibles" apt_remove "${WRONG_FLAVOR_PKGS[@]}" &&
    history_add "apt remove ${APT_REMOVALS[*]} (annuler : sudo apt-get install ${WRONG_FLAVOR_PKGS[*]})"
}

explain_module_source() {
  local k=$1 f=${KMOD_FILE[$1]:-} owner
  [[ -z $f ]] && return 0
  owner=$(dpkg -S "$f" 2>/dev/null | cut -d: -f1 | head -n1)
  if [[ -n $owner ]]; then
    note "Module utilisé pour $k : $f (paquet $owner)"
  elif [[ $f == */updates/dkms/* ]]; then
    note "Module utilisé pour $k : $f (compilé par DKMS)"
    note "Pour le reconstruire : sudo dkms autoinstall -k $k --force"
  else
    note "Module utilisé pour $k : $f (fichier qui n'appartient à aucun paquet)"
    note "Vérifie-le puis déplace-le hors de /lib/modules et lance : sudo depmod $k"
  fi
}

ubuntu_fix_kernel() {
  local k=$1 pre="linux-modules-nvidia-$BRANCH-$1"
  if pkg_available "$pre"; then
    if run "Module NVIDIA pré-compilé et signé pour $k" apt_install "$pre"; then
      history_add "apt install $pre"
      refresh_kernel "$k"
      module_ok "$k" && return 0
    fi
  fi
  if ! pkg_available "linux-headers-$k"; then
    fail "En-têtes introuvables pour $k : impossible de compiler le module"
    note "Noyau trop ancien ou retiré des dépôts. Démarre sur un noyau plus récent."
    FAILED+=("Module NVIDIA pour $k")
    return 1
  fi
  run "En-têtes du noyau $k" apt_install "linux-headers-$k" || return 1
  run "Paquet DKMS nvidia-dkms-$BRANCH" apt_install "nvidia-dkms-$BRANCH" || return 1
  USED_DKMS=1
  if ! run "Compilation du module NVIDIA pour $k (quelques minutes)" dkms autoinstall -k "$k"; then
    note "Journal de compilation : /var/lib/dkms/nvidia/*/build/make.log"
    return 1
  fi
  refresh_kernel "$k"
  if module_ok "$k"; then
    ok "Module $(flavor_label "${KMOD_FLAVOR[$k]}") prêt pour $k"
    return 0
  fi
  fail "Après installation, le module de $k est toujours $(flavor_label "${KMOD_FLAVOR[$k]}")"
  explain_module_source "$k"
  FAILED+=("Module NVIDIA $WANT_FLAVOR pour $k")
  return 1
}

ubuntu_fix() {
  if ! command -v apt-get &>/dev/null || ! command -v apt-cache &>/dev/null; then
    fail "APT est indisponible sur ce système : réparation impossible"
    FAILED+=("APT indisponible")
    return 1
  fi
  if ((DPKG_BROKEN)); then
    run "Réparation des paquets interrompus" dpkg --configure -a
    run "Réparation des dépendances" apt-get -o DPkg::Lock::Timeout=300 -f install -y
  fi
  run "Mise à jour de la liste des paquets" apt-get -o DPkg::Lock::Timeout=300 update ||
    warn "Liste des paquets non mise à jour (réseau ?) : on continue avec le cache local"
  local tools=()
  command -v ubuntu-drivers &>/dev/null || tools+=(ubuntu-drivers-common)
  command -v lspci &>/dev/null || tools+=(pciutils)
  [[ -d $ROOT/sys/firmware/efi ]] && ! command -v mokutil &>/dev/null && tools+=(mokutil)
  ((${#tools[@]})) && run "Outils nécessaires (${tools[*]})" apt_install "${tools[@]}"

  ubuntu_pick_branch || return 1

  if ! dpkg_installed "nvidia-driver-$BRANCH" | grep -q .; then
    apt_safe_install "Installation du pilote nvidia-driver-$BRANCH" "nvidia-driver-$BRANCH" || return 1
    [[ -n $SWITCH_FROM ]] && history_add "pilote $SWITCH_FROM -> nvidia-driver-$BRANCH (annuler : sudo apt-get install $SWITCH_FROM)"
  fi
  ubuntu_remove_wrong_flavor

  local k
  for k in "${KERNELS[@]}"; do
    refresh_kernel "$k"
    if module_ok "$k"; then
      ok "Module NVIDIA $(flavor_label "${KMOD_FLAVOR[$k]}") présent pour $k"
    else
      ubuntu_fix_kernel "$k"
    fi
  done
  classify_kernels

  local flavour
  while read -r flavour; do
    [[ -z $flavour ]] && continue
    if pkg_available "linux-modules-nvidia-$BRANCH-$flavour"; then
      run "Suivi automatique des futures mises à jour du noyau ($flavour)" \
        apt_install "linux-modules-nvidia-$BRANCH-$flavour"
    fi
    if ((USED_DKMS)) && pkg_available "linux-headers-$flavour"; then
      run "En-têtes automatiques pour les futurs noyaux ($flavour)" apt_install "linux-headers-$flavour"
    fi
  done < <(dpkg_installed 'linux-image-*' | grep -vE '^linux-image-(unsigned-)?[0-9]' | sed 's/^linux-image-//')

  if ! command -v nvidia-smi &>/dev/null; then
    local utils="nvidia-utils-${BRANCH%-open}"
    utils=${utils%-server}
    [[ $BRANCH == *-server* ]] && utils+="-server"
    pkg_available "$utils" && run "Outils NVIDIA ($utils)" apt_install "$utils"
  fi
}

ubuntu_finish() {
  run "Reconstruction de l'initramfs (tous les noyaux)" update-initramfs -u -k all ||
    note "Si /boot est plein : sudo apt autoremove --purge, puis relance le script."
  grub_manage
}

grub_manage() {
  [[ -w $GRUB_FILE ]] || ((OPT_DRY_RUN)) || return 0
  command -v update-grub &>/dev/null || return 0
  detect_kernels

  if module_ok "$NEWEST_KERNEL"; then
    if grep -q '# driver-fix' "$GRUB_FILE" 2>/dev/null; then
      run "Retour au noyau le plus récent par défaut" sed -i -E 's|^GRUB_DEFAULT=.*# driver-fix$|GRUB_DEFAULT=0|' "$GRUB_FILE"
      run "Mise à jour de GRUB" update-grub
    fi
    return 0
  fi

  local k best=""
  for k in "${KERNELS[@]}"; do module_ok "$k" && best=$k; done
  if [[ -z $best ]]; then
    fail "Aucun noyau n'a de module NVIDIA utilisable"
    return 1
  fi
  warn "Le noyau par défaut ($NEWEST_KERNEL) n'a pas de pilote NVIDIA utilisable"
  ask "Démarrer par défaut sur $best (qui a le pilote) ?" o || return 0

  local cfg=$ROOT/boot/grub/grub.cfg sub entry
  sub=$(sed -nE "s/^submenu .*menuentry_id_option '([^']+)'.*/\1/p" "$cfg" 2>/dev/null | head -n1)
  entry=$(sed -nE "s/.*menuentry_id_option '(gnulinux-${best//./\\.}-advanced-[^']+)'.*/\1/p" "$cfg" 2>/dev/null | head -n1)
  if [[ -z $sub || -z $entry ]]; then
    warn "Entrée GRUB introuvable : choisis $best dans « Options avancées » au démarrage"
    return 1
  fi
  [[ -e $GRUB_BACKUP ]] || run "Sauvegarde de /etc/default/grub" cp "$GRUB_FILE" "$GRUB_BACKUP" || return 1
  run "Noyau par défaut → $best" sed -i -E "s|^#?[[:space:]]*GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$sub>$entry\" # driver-fix|" "$GRUB_FILE"
  run "Mise à jour de GRUB" update-grub && GRUB_PINNED=$best && history_add "GRUB par défaut -> $best (annuler : sudo bash fix.sh --undo)"
}

debian_fix() {
  if ! command -v apt-get &>/dev/null; then
    fail "APT est indisponible"; FAILED+=("APT indisponible"); return 1
  fi
  if ((DPKG_BROKEN)); then
    run "Réparation des paquets interrompus" dpkg --configure -a
  fi
  run "Mise à jour de la liste des paquets" apt-get -o DPkg::Lock::Timeout=300 update
  if ! pkg_available nvidia-driver; then
    fail "Le paquet nvidia-driver est introuvable"
    note "Active les composants « contrib non-free non-free-firmware » dans /etc/apt/sources.list"
    note "puis relance le script. Doc : https://wiki.debian.org/NvidiaGraphicsDrivers"
    FAILED+=("Installation du pilote NVIDIA")
    return 1
  fi
  local k pkgs=(nvidia-driver firmware-misc-nonfree)
  if [[ $WANT_FLAVOR == open ]]; then
    if pkg_available nvidia-open-kernel-dkms; then
      pkgs+=(nvidia-open-kernel-dkms)
    else
      warn "Ce GPU exige les modules open, mais nvidia-open-kernel-dkms est introuvable"
    fi
  fi
  for k in "${KERNELS[@]}"; do
    pkg_available "linux-headers-$k" && run "En-têtes du noyau $k" apt_install "linux-headers-$k"
  done
  local meta
  meta=$(dpkg_installed 'linux-image-*' | grep -vE '^linux-image-[0-9]' | head -n1)
  [[ -n $meta ]] && run "En-têtes automatiques pour les futurs noyaux" apt_install "${meta/image/headers}"
  apt_safe_install "Installation du pilote (${pkgs[*]})" "${pkgs[@]}" || return 1
  USED_DKMS=1
  for k in "${KERNELS[@]}"; do
    refresh_kernel "$k"
    module_ok "$k" || run "Compilation du module NVIDIA pour $k" dkms autoinstall -k "$k"
  done
}

fedora_fix() {
  if ! dnf repolist --enabled 2>/dev/null | grep -qi rpmfusion-nonfree; then
    local v
    v=$(rpm -E %fedora)
    ask "Activer les dépôts tiers RPM Fusion (nécessaires au pilote NVIDIA) ?" o || return 1
    run "Activation des dépôts RPM Fusion" dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$v.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$v.noarch.rpm" || return 1
  fi
  run "Installation du pilote (akmod-nvidia)" dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda kernel-devel || return 1
  USED_DKMS=1
  local k
  for k in "${KERNELS[@]}"; do
    refresh_kernel "$k"
    module_ok "$k" && continue
    run "En-têtes du noyau $k" dnf install -y "kernel-devel-$k"
    run "Compilation du module NVIDIA pour $k (quelques minutes)" akmods --force --kernels "$k"
  done
  run "Reconstruction de l'initramfs" dracut --force --regenerate-all
}

arch_fix() {
  if ((!NV_TURING)); then
    fail "Carte d'avant 2018 : le pilote officiel d'Arch ne la gère plus"
    note "Installe nvidia-580xx-dkms depuis l'AUR (ex : yay -S nvidia-580xx-dkms)"
    FAILED+=("Installation du pilote NVIDIA")
    return 1
  fi
  local pkgs=(nvidia-open-dkms nvidia-utils dkms) kp old=()
  for kp in linux linux-lts linux-zen linux-hardened linux-rt linux-rt-lts; do
    pacman -Q "$kp" &>/dev/null && pkgs+=("$kp-headers")
  done
  for kp in nvidia nvidia-open nvidia-lts nvidia-open-lts; do
    pacman -Q "$kp" &>/dev/null && old+=("$kp")
  done
  if ((${#old[@]})); then
    warn "Paquets à remplacer par la version DKMS : ${old[*]}"
    ask "Les retirer (sans toucher au reste) ?" o || return 1
    run "Retrait de ${old[*]}" pacman -Rdd --noconfirm "${old[@]}" || return 1
  fi
  run "Mise à jour du système + pilote nvidia-open-dkms" pacman -Syu --needed --noconfirm "${pkgs[@]}" || return 1
  USED_DKMS=1
  detect_kernels
  local k
  for k in "${KERNELS[@]}"; do
    module_ok "$k" || run "Compilation du module NVIDIA pour $k" dkms autoinstall -k "$k"
  done
  if command -v mkinitcpio &>/dev/null; then
    run "Reconstruction de l'initramfs" mkinitcpio -P
  elif command -v dracut &>/dev/null; then
    run "Reconstruction de l'initramfs" dracut --force --regenerate-all
  fi
}

no_nvidia() {
  box "$CYN" \
    "${B}Aucune carte NVIDIA détectée.${R}" \
    "" \
    "Les pilotes AMD et Intel sont déjà inclus dans le noyau Linux :" \
    "il n'y a rien à installer. Si l'HDMI ne marche pas :" \
    "  • mets à jour le système (le firmware est dans « linux-firmware »)" \
    "  • redémarre avec le câble HDMI déjà branché" \
    "  • essaie un autre câble ou une autre entrée sur l'écran"
  if [[ $FAMILY == ubuntu || $FAMILY == debian ]] && ((!OPT_DIAGNOSE)) && command -v apt-get &>/dev/null; then
    if ask "Mettre à jour linux-firmware maintenant ?" o; then
      run "Mise à jour de la liste des paquets" apt-get -o DPkg::Lock::Timeout=300 update
      run "Mise à jour de linux-firmware" apt_install --only-upgrade linux-firmware
    fi
  fi
}

show_system() {
  step "Analyse du système"
  kv "Distribution" "$DISTRO_NAME"
  local fam
  case $FAMILY in
    ubuntu) fam="${GRN}support complet${R}" ;;
    debian | fedora | arch) fam="${YLW}support expérimental${R}" ;;
    *) fam="${RED}non supportée${R}" ;;
  esac
  kv "Support" "$fam"
  kv "Noyau actuel" "$RUNNING_KERNEL"
  kv "Noyaux installés" "${KERNELS[*]}"
  case $SECURE_BOOT in
    on) kv "Secure Boot" "${YLW}activé${R}" ;;
    off) kv "Secure Boot" "désactivé" ;;
    legacy) kv "Secure Boot" "BIOS legacy (pas de Secure Boot)" ;;
  esac
}

show_gpus() {
  step "Carte graphique"
  local g name drv icon rest c
  for g in "${GPU_LINES[@]}"; do
    name=${g%%|*} rest=${g#*|} drv=${rest%%|*}
    case $drv in
      nvidia | amdgpu | i915 | xe) icon="${GRN}●${R}" ;;
      nouveau | "aucun pilote") icon="${RED}●${R}" ;;
      *) icon="${YLW}●${R}" ;;
    esac
    printf '  %s %s%s%s\n' "$icon" "$B" "$name" "$R"
    note "pilote utilisé : $drv · ${rest#*|}"
  done
  ((${#GPU_LINES[@]} == 0)) && warn "Aucune carte graphique trouvée sur le bus PCI"
  ((HAS_NVIDIA)) || return 0
  ((HAS_OTHER_GPU)) && kv "Type" "portable hybride (iGPU + NVIDIA)"
  kv "ID PCI NVIDIA" "10de:$NV_DEVICE_ID"
  [[ -n $NV_DRIVER_VERSION ]] && kv "Pilote chargé" "$NV_DRIVER_VERSION ($(flavor_label "${NV_LOADED_FLAVOR:-none}"))"
  kv "Module sur disque" "$(flavor_label "${KMOD_FLAVOR[$RUNNING_KERNEL]:-none}")${KMOD_VERSION[$RUNNING_KERNEL]:+ ${KMOD_VERSION[$RUNNING_KERNEL]}}"
  [[ $WANT_FLAVOR != any ]] && kv "Variante requise" "$WANT_FLAVOR"
  ((${#NV_PKGS[@]})) && kv "Paquets" "$(printf '%s ' "${DRIVER_PKGS[@]}")"
  case $NV_SMI_STATE in
    ok) kv "nvidia-smi" "${GRN}fonctionne${R}" ;;
    absent) kv "nvidia-smi" "${YLW}absent${R}" ;;
    *) kv "nvidia-smi" "${RED}${NV_SMI_MSG:-ne répond pas}${R}" ;;
  esac
  [[ -n $PRIME_MODE ]] && kv "Mode PRIME" "$PRIME_MODE"
  for c in "${CONNECTOR_LINES[@]}"; do
    IFS='|' read -r name drv rest <<<"$c"
    kv "Sortie $name" "$rest (carte $drv)"
  done
}

show_diagnosis() {
  step "Diagnostic"
  local p
  for p in "${PROBLEMS[@]}"; do fail "$p"; done
  for p in "${WARNINGS[@]}"; do warn "$p"; done
  for p in "${ADVICE[@]}"; do info "$p"; done
  if ((${#PROBLEMS[@]} == 0 && ${#WARNINGS[@]} == 0)); then
    ok "Aucun problème détecté côté pilote 🎉"
  fi
}

apply_fixes() {
  step "Réparation"
  local rc=0
  case $FAMILY in
    ubuntu) ubuntu_fix || rc=1 ;;
    debian) debian_fix || rc=1 ;;
    fedora) fedora_fix || rc=1 ;;
    arch) arch_fix || rc=1 ;;
  esac
  ((rc)) && warn "Étape d'installation incomplète : on n'applique que les réglages sans risque"
  detect_kernels
  configure_modprobe
  fix_prime
  case $FAMILY in
    ubuntu | debian) ubuntu_finish ;;
  esac
  secure_boot_enroll
}

verify() {
  step "Vérification"
  ((OPT_DRY_RUN)) && { note "(simulation : rien n'a été modifié)"; return; }
  detect_kernels
  local k tag sig all_ok=1
  for k in "${KERNELS[@]}"; do
    tag=""
    [[ $k == "$RUNNING_KERNEL" ]] && tag+=" ${D}· actuel${R}"
    if [[ -n $GRUB_PINNED ]]; then
      [[ $k == "$GRUB_PINNED" ]] && tag+=" ${CYN}· démarrage par défaut${R}"
    elif [[ $k == "$NEWEST_KERNEL" ]]; then
      tag+=" ${CYN}· démarrage par défaut${R}"
    fi
    sig=""
    [[ $SECURE_BOOT == on && -z ${KMOD_SIGNER[$k]:-} && ${KMOD_FLAVOR[$k]} != none ]] && sig=" ${YLW}(non signé)${R}"
    if module_ok "$k"; then
      printf '  %s✔%s %-26s module %s%s%s\n' "$GRN" "$R" "$k" "$(flavor_label "${KMOD_FLAVOR[$k]}")" "$sig" "$tag"
    else
      [[ $k == "$NEWEST_KERNEL" || $k == "$RUNNING_KERNEL" ]] && all_ok=0
      printf '  %s✖%s %-26s module %s%s\n' "$RED" "$R" "$k" "$(flavor_label "${KMOD_FLAVOR[$k]}")" "$tag"
    fi
  done
  ((all_ok)) || FAILED+=("Module NVIDIA utilisable pour le noyau par défaut")

  probe_nvidia_smi
  if ((NV_SMI_OK)) && ((DONE_COUNT == 0)); then
    GPU_WORKING_NOW=1
    ok "nvidia-smi voit le GPU : le pilote fonctionne déjà"
  else
    REBOOT_NEEDED=1
    info "Le nouveau pilote sera actif au prochain démarrage."
  fi
  save_last_run
}

final_message() {
  if ((OPT_DRY_RUN)); then
    box "$CYN" "${B}Simulation terminée${R} : aucune modification n'a été faite." \
      "Relance sans --dry-run pour appliquer la réparation."
    return
  fi

  if ((${#FAILED[@]})); then
    local lines=("${YLW}${B}⚠ Réparation terminée avec ${#FAILED[@]} erreur(s) :${R}")
    local f
    for f in "${FAILED[@]}"; do lines+=("  • $f"); done
    lines+=("" "Détails dans le journal : $LOG_FILE")
    box "$YLW" "${lines[@]}"
  fi

  if ((MOK_PENDING)); then
    box "$MAG" \
      "${B}IMPORTANT — au redémarrage, un écran BLEU va apparaître${R}" \
      "" \
      "  1. Appuie sur une touche, puis choisis « Enroll MOK »" \
      "  2. « Continue » puis « Yes »" \
      "  3. Tape le mot de passe : ${B}${MOK_PASSWORD:-celui choisi dans le terminal}${R}" \
      "  4. « Reboot »" \
      "" \
      "${D}Mot de passe aussi dans $STATE_DIR/mok-password (root).${R}" \
      "${D}Si tu rates cet écran, relance simplement le script.${R}"
  fi

  if ((${#FAILED[@]} == 0 && GPU_WORKING_NOW)); then
    box "$GRN" "${GRN}${B}✔ Le pilote NVIDIA fonctionne.${R}" "" \
      "Si l'HDMI reste noir : rebranche le câble ou teste une autre entrée." \
      "${D}Annuler les réglages : sudo bash fix.sh --undo${R}"
    return
  fi

  local title="${GRN}${B}Correctif installé — redémarrage nécessaire${R}"
  ((${#FAILED[@]})) && title="${YLW}${B}Réparation partielle appliquée${R}"
  box "$GRN" \
    "$title" \
    "" \
    "${B}➜ Redémarre ton PC pour terminer.${R}" \
    "" \
    "${D}HDMI toujours noir ? essaie : sudo prime-select nvidia${R}" \
    "${D}Annuler les réglages : sudo bash fix.sh --undo${R}" \
    "${D}Aide : $REPO_URL${R}"

  if ((HAS_TTY && !OPT_YES)) && ask "Redémarrer maintenant ?" n; then
    info "Redémarrage dans 5 secondes… (Ctrl+C pour annuler)"
    sleep 5
    systemctl reboot
  fi
}

undo() {
  step "Annulation des réglages driver-fix"
  local files=() f
  for f in "$CONF_PREFIX"-*.conf; do [[ -e $f ]] && files+=("$f"); done
  if ((${#files[@]} == 0)) && [[ ! -e $GRUB_BACKUP ]]; then
    ok "Aucun réglage driver-fix à annuler"
  else
    ((${#files[@]})) && info "Fichiers à retirer : ${files[*]}"
    [[ -e $GRUB_BACKUP ]] && info "GRUB : restauration de $GRUB_BACKUP"
    if ask "Annuler ces réglages ?" o; then
      for f in "${files[@]}"; do run "Retrait de $f" rm -f "$f"; done
      if [[ -e $GRUB_BACKUP ]]; then
        run "Restauration de /etc/default/grub" cp "$GRUB_BACKUP" "$GRUB_FILE" &&
          run "Suppression de la sauvegarde GRUB" rm -f "$GRUB_BACKUP"
        command -v update-grub &>/dev/null && run "Mise à jour de GRUB" update-grub
      fi
      if command -v update-initramfs &>/dev/null; then
        run "Reconstruction de l'initramfs" update-initramfs -u -k all
      elif command -v dracut &>/dev/null; then
        run "Reconstruction de l'initramfs" dracut --force --regenerate-all
      fi
      history_add "undo : réglages retirés"
    fi
  fi
  if [[ -r $STATE_DIR/history.log ]]; then
    printf '\n'
    info "Changements de paquets faits par le script (non annulés automatiquement) :"
    grep -E 'apt |pilote |prime-select' "$STATE_DIR/history.log" | tail -n 15 | while IFS= read -r f; do note "$f"; done
  fi
}

usage() {
  cat <<EOF
driver-fix v$VERSION — répare l'HDMI / écran externe des PC Linux avec carte NVIDIA

Usage :
  sudo ./fix.sh [options]
  curl -fsSL $RAW_URL | sudo bash -s -- [options]

Options :
  -d, --diagnose      Analyse seulement, ne modifie rien
  -n, --dry-run       Montre ce qui serait fait, sans rien modifier
  -i, --interactive   Pose les questions au lieu de tout faire automatiquement
  -p, --prime MODE    Force le mode PRIME : on-demand | nvidia | intel
      --undo          Retire les réglages ajoutés par le script (modprobe, GRUB)
      --no-color      Désactive les couleurs
  -h, --help          Affiche cette aide

Journal : /var/log/driver-fix.log · Historique : /var/lib/driver-fix/history.log
Plus d'infos : $REPO_URL
EOF
}

parse_args() {
  while (($#)); do
    case $1 in
      -d | --diagnose) OPT_DIAGNOSE=1 ;;
      -n | --dry-run) OPT_DRY_RUN=1 ;;
      -y | --yes) OPT_YES=1 ;;
      -i | --interactive) OPT_YES=0 ;;
      -p | --prime)
        OPT_PRIME=${2:-}
        [[ $OPT_PRIME =~ ^(on-demand|nvidia|intel)$ ]] || { echo "Mode PRIME invalide : $OPT_PRIME" >&2; exit 1; }
        shift
        ;;
      --undo) OPT_UNDO=1 ;;
      --no-color) OPT_NO_COLOR=1 ;;
      -h | --help) usage; exit 0 ;;
      *) echo "Option inconnue : $1 (voir --help)" >&2; exit 1 ;;
    esac
    shift
  done
}

ensure_root() {
  [[ $EUID -eq 0 ]] && return 0
  [[ -n ${DRIVER_FIX_TEST:-} ]] && return 0
  if ((OPT_DIAGNOSE || OPT_DRY_RUN)); then
    warn "Lancé sans sudo : certaines infos peuvent manquer"
    return 0
  fi
  info "Les droits administrateur sont nécessaires, sudo va te demander ton mot de passe."
  if [[ -f $0 && -r $0 ]]; then
    exec sudo bash "$0" "$@"
  fi
  if command -v curl &>/dev/null; then
    exec sudo bash -c "$(curl -fsSL "$RAW_URL")" driver-fix "$@"
  elif command -v wget &>/dev/null; then
    exec sudo bash -c "$(wget -qO- "$RAW_URL")" driver-fix "$@"
  fi
  fail "Relance avec sudo : sudo bash fix.sh"
  exit 1
}

take_lock() {
  ((OPT_DIAGNOSE || OPT_DRY_RUN)) && return 0
  command -v flock &>/dev/null || return 0
  local lock=$ROOT/run/driver-fix.lock
  mkdir -p "$(dirname "$lock")" 2>/dev/null
  exec 9>"$lock" || return 0
  flock -n 9 || { fail "driver-fix est déjà en cours d'exécution"; exit 1; }
}

main() {
  parse_args "$@"
  setup_colors
  if [[ -z ${DRIVER_FIX_TEST:-} ]]; then
    { : </dev/tty; } 2>/dev/null && HAS_TTY=1
  fi
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' && export LC_CTYPE=C.UTF-8

  ensure_root "$@"
  if [[ -n ${DRIVER_FIX_LOG:-} ]]; then LOG_FILE=$DRIVER_FIX_LOG
  elif [[ $EUID -eq 0 ]]; then LOG_FILE=/var/log/driver-fix.log
  else LOG_FILE=${TMPDIR:-/tmp}/driver-fix-${USER:-user}.log; fi
  export DEBIAN_FRONTEND=noninteractive
  trap '((FANCY)) && printf "\e[?25h"' EXIT
  trap 'printf "\e[?25h\n"; warn "Interrompu. Relance le script : il reprend là où il en était (dpkg --configure -a si besoin)."; exit 130' INT TERM
  take_lock

  {
    printf '\n===== driver-fix v%s — %s =====\n' "$VERSION" "$(date '+%F %T')"
    uname -a
    printf 'Options : %s\n' "$*"
  } >>"$LOG_FILE" 2>/dev/null

  banner
  ((OPT_DRY_RUN)) && printf '  %sMode simulation : rien ne sera modifié%s\n' "$YLW" "$R"
  ((OPT_DIAGNOSE)) && printf '  %sMode diagnostic : rien ne sera modifié%s\n' "$YLW" "$R"

  if ((OPT_UNDO)); then
    TOTAL_STEPS=1
    undo
    exit 0
  fi

  detect_distro
  detect_kernels
  detect_gpus
  detect_connectors
  detect_secure_boot
  detect_driver_state
  detect_packages
  detect_last_run
  decide_flavor
  analyze

  show_system
  show_gpus

  if ((!HAS_NVIDIA)); then
    no_nvidia
    exit 0
  fi

  show_diagnosis
  {
    printf 'Distribution: %s %s (%s) | Noyaux: %s\n' "$DISTRO_ID" "$DISTRO_VERSION" "$FAMILY" "${KERNELS[*]}"
    printf 'GPU 10de:%s @ %s | chargé: %s | requis: %s | nvidia-smi: %s\n' \
      "$NV_DEVICE_ID" "$NV_PCI_ADDR" "${NV_LOADED_FLAVOR:-non}" "$WANT_FLAVOR" "$NV_SMI_STATE"
    local k
    for k in "${KERNELS[@]}"; do printf 'Module %s: %s %s %s\n' "$k" "${KMOD_FLAVOR[$k]}" "${KMOD_VERSION[$k]}" "${KMOD_FILE[$k]}"; done
    printf 'Problèmes:\n'; printf '  - %s\n' "${PROBLEMS[@]}" "${WARNINGS[@]}"
  } >>"$LOG_FILE" 2>/dev/null

  if ((OPT_DIAGNOSE)); then
    printf '\n'
    info "Pour réparer, relance sans --diagnose."
    exit 0
  fi

  case $FAMILY in
    manjaro)
      box "$YLW" "Manjaro gère les pilotes avec son propre outil. Lance :" \
        "  ${B}sudo mhwd -a pci nonfree 0300${R}" "puis redémarre."
      exit 1
      ;;
    unknown)
      box "$RED" "Distribution non supportée : $DISTRO_NAME" \
        "Ouvre une issue sur $REPO_URL" "en collant le résultat de --diagnose."
      exit 1
      ;;
  esac

  if ((${#PROBLEMS[@]} == 0)) && ((OPT_YES)); then
    info "Rien à réparer : le pilote NVIDIA est en place. Bonne journée !"
    exit 0
  elif ((${#PROBLEMS[@]} == 0)); then
    note "Le script peut quand même vérifier et sécuriser l'installation"
    note "(pilote installé pour tous les noyaux, futures mises à jour, etc.)."
    ask "Lancer la réparation préventive ?" n || { info "Rien à faire. Bonne journée !"; exit 0; }
  else
    ask "Lancer la réparation automatique ?" o || { info "Annulé, rien n'a été modifié."; exit 0; }
  fi

  apply_fixes
  verify
  final_message
  ((${#FAILED[@]} == 0))
}

[[ -n ${DRIVER_FIX_SOURCED:-} ]] || main "$@"
