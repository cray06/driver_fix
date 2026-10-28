#!/usr/bin/env bash

VERSION="1.0.0"
REPO_URL="https://github.com/cray06/driver_fix"
RAW_URL="https://raw.githubusercontent.com/cray06/driver_fix/main/fix.sh"
CONF_PREFIX="/etc/modprobe.d/driver-fix"

OPT_DIAGNOSE=0
OPT_DRY_RUN=0
OPT_YES=0
OPT_NO_COLOR=0
OPT_PRIME=""

FAMILY="" DISTRO_NAME="" RUNNING_KERNEL="" NEWEST_KERNEL=""
KERNELS=() MISSING_KERNELS=()
GPU_LINES=() HAS_NVIDIA=0 HAS_OTHER_GPU=0 NV_DEVICE_ID="" NV_TURING=0
NV_LOADED=0 NOUVEAU_LOADED=0 NV_SMI_OK=0 NV_MISMATCH=0 NV_DRIVER_VERSION=""
SECURE_BOOT="off" KEY_REJECTED=0 PRIME_MODE="" MODESET="" DPKG_BROKEN=0
PROBLEMS=() WARNINGS=()

BRANCH="" USED_DKMS=0 MOK_PENDING=0 GRUB_PINNED=""
DONE_COUNT=0 FAILED=()
STEP=0 TOTAL_STEPS=5
HAS_TTY=0 FANCY=0

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

ok()   { printf '  %s✔%s %s\n' "$GRN" "$R" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$YLW" "$R" "$*"; }
fail() { printf '  %s✖%s %s\n' "$RED" "$R" "$*"; }
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
  ((OPT_YES)) && return 0
  if ((!HAS_TTY)); then [[ $def == o ]]; return; fi
  [[ $def == o ]] && hint="[O/n]" || hint="[o/N]"
  printf '\n  %s?%s %s%s%s %s%s%s ' "$BLU" "$R" "$B" "$question" "$R" "$D" "$hint" "$R"
  read -r ans </dev/tty || ans=""
  ans=${ans,,}
  [[ -z $ans ]] && ans=$def
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
  printf '%s\n' "$2" >"$1"
}

detect_distro() {
  [[ -r /etc/os-release ]] && . /etc/os-release
  DISTRO_NAME=${PRETTY_NAME:-${ID:-inconnue}}
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
  for d in /lib/modules/*/; do
    k=$(basename "$d")
    [[ -e /boot/vmlinuz-$k || -e /lib/modules/$k/vmlinuz ]] && printf '%s\n' "$k"
  done | sort -V
}

has_nv_module() { modinfo -k "$1" nvidia &>/dev/null; }

detect_kernels() {
  RUNNING_KERNEL=$(uname -r)
  mapfile -t KERNELS < <(list_kernels)
  ((${#KERNELS[@]} == 0)) && KERNELS=("$RUNNING_KERNEL")
  NEWEST_KERNEL=${KERNELS[-1]}
  MISSING_KERNELS=()
  local k
  for k in "${KERNELS[@]}"; do
    has_nv_module "$k" || MISSING_KERNELS+=("$k")
  done
}

detect_gpus() {
  local d class vendor device name drv
  GPU_LINES=() HAS_NVIDIA=0 HAS_OTHER_GPU=0
  for d in /sys/bus/pci/devices/*; do
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
        ((16#$NV_DEVICE_ID >= 16#1e00)) && NV_TURING=1
        [[ -z $name ]] && name="NVIDIA [10de:$NV_DEVICE_ID]"
        ;;
      0x1002) HAS_OTHER_GPU=1; [[ -z $name ]] && name="AMD [1002:${device#0x}]" ;;
      0x8086) HAS_OTHER_GPU=1; [[ -z $name ]] && name="Intel [8086:${device#0x}]" ;;
      *) HAS_OTHER_GPU=1; [[ -z $name ]] && name="GPU [${vendor#0x}:${device#0x}]" ;;
    esac
    GPU_LINES+=("$name|${drv:-aucun pilote}")
  done
}

detect_secure_boot() {
  SECURE_BOOT="off"
  if [[ ! -d /sys/firmware/efi ]]; then SECURE_BOOT="legacy"; return; fi
  if command -v mokutil &>/dev/null; then
    mokutil --sb-state 2>/dev/null | grep -qi 'SecureBoot enabled' && SECURE_BOOT="on"
    return
  fi
  local f
  for f in /sys/firmware/efi/efivars/SecureBoot-*; do
    [[ -r $f ]] && [[ $(od -An -t u1 -j4 -N1 "$f" | tr -d ' ') == 1 ]] && SECURE_BOOT="on"
  done
}

detect_driver_state() {
  [[ -d /sys/module/nvidia ]] && NV_LOADED=1
  [[ -d /sys/module/nouveau ]] && NOUVEAU_LOADED=1
  [[ -r /sys/module/nvidia_drm/parameters/modeset ]] && MODESET=$(</sys/module/nvidia_drm/parameters/modeset)
  [[ -r /sys/module/nvidia/version ]] && NV_DRIVER_VERSION=$(</sys/module/nvidia/version)

  if command -v nvidia-smi &>/dev/null; then
    local out
    out=$(timeout 15 nvidia-smi 2>&1) && NV_SMI_OK=1
    grep -qi 'version mismatch' <<<"$out" && NV_MISMATCH=1
  fi

  local klog
  klog=$( (journalctl -k -b 0 --no-pager 2>/dev/null || dmesg 2>/dev/null) | grep -i nvidia)
  grep -Eqi 'key was rejected|unavailable key|required key not available|unsigned module' <<<"$klog" && KEY_REJECTED=1
  grep -qi 'API mismatch' <<<"$klog" && NV_MISMATCH=1

  command -v prime-select &>/dev/null && PRIME_MODE=$(prime-select query 2>/dev/null)
  if [[ $FAMILY == ubuntu || $FAMILY == debian ]]; then
    [[ -n $(dpkg --audit 2>/dev/null) ]] && DPKG_BROKEN=1
  fi
}

nv_installed() {
  ((${#MISSING_KERNELS[@]} < ${#KERNELS[@]})) || command -v nvidia-smi &>/dev/null
}

analyze() {
  PROBLEMS=() WARNINGS=()
  ((DPKG_BROKEN)) && PROBLEMS+=("Des paquets sont à moitié installés (apt/dpkg interrompu)")
  if ! nv_installed; then
    PROBLEMS+=("Aucun pilote NVIDIA n'est installé")
  else
    local k tag
    for k in "${MISSING_KERNELS[@]}"; do
      if [[ $k == "$RUNNING_KERNEL" ]]; then
        PROBLEMS+=("Pas de module NVIDIA pour le noyau actuel ($k)")
      elif [[ $k == "$NEWEST_KERNEL" ]]; then
        PROBLEMS+=("Pas de module NVIDIA pour le noyau du prochain démarrage ($k)")
      else
        WARNINGS+=("Pas de module NVIDIA pour l'ancien noyau $k (secours)")
      fi
    done
  fi
  ((KEY_REJECTED)) && PROBLEMS+=("Secure Boot bloque le module NVIDIA (clé non enregistrée)")
  ((NV_MISMATCH)) && PROBLEMS+=("Le pilote a été mis à jour sans redémarrer (version mismatch)")
  ((NOUVEAU_LOADED)) && PROBLEMS+=("Le pilote libre « nouveau » est utilisé à la place du pilote NVIDIA")
  if [[ $PRIME_MODE == intel ]]; then
    PROBLEMS+=("Mode PRIME « intel » : la carte NVIDIA est éteinte (le port HDMI est souvent relié à elle)")
  fi
  if ((NV_LOADED)) && [[ $MODESET == N ]]; then
    PROBLEMS+=("L'option nvidia-drm modeset est désactivée")
  fi
  if nv_installed && ((!NV_LOADED)) && ((!NOUVEAU_LOADED)) && ((!KEY_REJECTED)) && has_nv_module "$RUNNING_KERNEL"; then
    WARNINGS+=("Le module NVIDIA existe mais n'est pas chargé (un redémarrage est sûrement nécessaire)")
  fi
  if [[ $RUNNING_KERNEL != "$NEWEST_KERNEL" ]]; then
    WARNINGS+=("Le PC tourne sur $RUNNING_KERNEL alors que $NEWEST_KERNEL est installé (pas redémarré depuis une mise à jour ?)")
  fi
}

configure_modprobe() {
  run "Désactivation du pilote libre « nouveau »" write_file "$CONF_PREFIX-nouveau.conf" \
"# Ajouté par driver-fix ($REPO_URL)
blacklist nouveau
options nouveau modeset=0"
  run "Activation de nvidia-drm modeset (nécessaire pour l'HDMI)" write_file "$CONF_PREFIX-nvidia.conf" \
"# Ajouté par driver-fix ($REPO_URL)
options nvidia-drm modeset=1"
}

fix_prime() {
  command -v prime-select &>/dev/null || return 0
  ((HAS_OTHER_GPU)) || return 0
  local target=$OPT_PRIME
  if [[ -z $target ]]; then
    [[ $PRIME_MODE == intel || -z $PRIME_MODE ]] && target="on-demand" || return 0
  fi
  [[ $target == "$PRIME_MODE" ]] && { ok "Mode PRIME déjà sur « $target »"; return 0; }
  run "Mode PRIME : $PRIME_MODE → $target" prime-select "$target"
}

secure_boot_enroll() {
  [[ $SECURE_BOOT == on ]] || return 0
  if [[ $FAMILY == ubuntu ]] && ((!USED_DKMS && !KEY_REJECTED)) && ! dkms status 2>/dev/null | grep -qi nvidia; then
    ok "Secure Boot : le module NVIDIA utilisé est signé par Ubuntu"
    return 0
  fi
  command -v mokutil &>/dev/null || { warn "mokutil absent : impossible d'enregistrer la clé Secure Boot"; return 1; }
  local key
  for key in /var/lib/shim-signed/mok/MOK.der /var/lib/dkms/mok.pub /etc/pki/akmods/certs/public_key.der; do
    [[ -r $key ]] || continue
    if mokutil --test-key "$key" 2>&1 | grep -qi 'already enrolled'; then
      ok "Secure Boot : clé de signature déjà enregistrée"
      return 0
    fi
    if ((OPT_DRY_RUN)); then
      run "Enregistrement de la clé Secure Boot" mokutil --import "$key"
      return 0
    fi
    box "$YLW" \
      "${B}Secure Boot est activé${R}" \
      "Il faut enregistrer une clé pour autoriser le pilote NVIDIA." \
      "" \
      "Choisis un mot de passe simple (ex : ${B}12345678${R})." \
      "Tu devras le retaper UNE fois au prochain démarrage."
    if ((!HAS_TTY)); then
      warn "Pas de terminal interactif. Lance ensuite : sudo mokutil --import $key"
      FAILED+=("Enregistrement de la clé Secure Boot")
      return 1
    fi
    printf '\n'
    if mokutil --import "$key" </dev/tty; then
      MOK_PENDING=1
      ok "Clé Secure Boot prête à être enregistrée au redémarrage"
    else
      fail "Échec de mokutil --import"
      FAILED+=("Enregistrement de la clé Secure Boot")
    fi
    return 0
  done
  warn "Secure Boot activé mais aucune clé de signature trouvée"
  note "Si l'écran reste noir, désactive Secure Boot dans le BIOS."
}

apt_install() { apt-get -o DPkg::Lock::Timeout=300 install -y "$@"; }
pkg_available() { apt-cache show "$1" &>/dev/null; }
dpkg_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}|${Package}\n' "$@" 2>/dev/null | awk -F'|' '$1 ~ /^ii/ {print $2}'
}

ubuntu_pick_branch() {
  local pkg
  pkg=$(dpkg_installed 'nvidia-driver-*' | grep -E '^nvidia-driver-[0-9]+(-server)?(-open)?$' | sort -V | tail -n1)
  if [[ -n $pkg ]]; then
    BRANCH=${pkg#nvidia-driver-}
    ok "Pilote déjà installé : ${B}$pkg${R}"
    return 0
  fi
  if command -v ubuntu-drivers &>/dev/null; then
    pkg=$(ubuntu-drivers devices 2>/dev/null | awk '/nvidia-driver-.*recommended/ {print $3; exit}')
  fi
  if [[ -z $pkg ]]; then
    local suffix='-open'
    ((NV_TURING)) || suffix=''
    pkg=$(apt-cache pkgnames nvidia-driver- 2>/dev/null | grep -E "^nvidia-driver-[0-9]+$suffix\$" | sort -V |
      awk -v t="$NV_TURING" '{ split($0, a, "-"); if (t == 1 || a[3] + 0 <= 580) last = $0 } END { print last }')
  fi
  if [[ -z $pkg ]]; then
    fail "Impossible de trouver un pilote NVIDIA dans les dépôts"
    FAILED+=("Choix du pilote NVIDIA")
    return 1
  fi
  BRANCH=${pkg#nvidia-driver-}
  ok "Pilote recommandé pour ta carte : ${B}$pkg${R}"
}

ubuntu_fix_kernel() {
  local k=$1 pre="linux-modules-nvidia-$BRANCH-$1"
  if pkg_available "$pre"; then
    run "Module NVIDIA pré-compilé pour $k" apt_install "$pre" && return 0
  fi
  if ! pkg_available "linux-headers-$k"; then
    fail "En-têtes introuvables pour $k (noyau trop ancien ?)"
    FAILED+=("Module NVIDIA pour $k")
    return 1
  fi
  run "En-têtes du noyau $k" apt_install "linux-headers-$k" || return 1
  run "Paquet DKMS nvidia-dkms-$BRANCH" apt_install "nvidia-dkms-$BRANCH" || return 1
  USED_DKMS=1
  run "Compilation du module NVIDIA pour $k (quelques minutes)" dkms autoinstall -k "$k"
}

ubuntu_fix() {
  if ((DPKG_BROKEN)); then
    run "Réparation des paquets interrompus" dpkg --configure -a
    run "Réparation des dépendances" apt-get -o DPkg::Lock::Timeout=300 -f install -y
  fi
  run "Mise à jour de la liste des paquets" apt-get -o DPkg::Lock::Timeout=300 update
  local tools=()
  command -v ubuntu-drivers &>/dev/null || tools+=(ubuntu-drivers-common)
  command -v lspci &>/dev/null || tools+=(pciutils)
  [[ -d /sys/firmware/efi ]] && ! command -v mokutil &>/dev/null && tools+=(mokutil)
  ((${#tools[@]})) && run "Outils nécessaires (${tools[*]})" apt_install "${tools[@]}"

  ubuntu_pick_branch || return 1

  if ! dpkg_installed "nvidia-driver-$BRANCH" | grep -q .; then
    run "Installation du pilote nvidia-driver-$BRANCH" apt_install "nvidia-driver-$BRANCH" || return 1
  fi

  local k
  for k in "${KERNELS[@]}"; do
    if has_nv_module "$k"; then
      ok "Module NVIDIA présent pour $k"
    else
      ubuntu_fix_kernel "$k"
    fi
  done

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
}

ubuntu_finish() {
  run "Reconstruction de l'initramfs (tous les noyaux)" update-initramfs -u -k all
  grub_manage
}

grub_manage() {
  [[ -w /etc/default/grub ]] || ((OPT_DRY_RUN)) || return 0
  command -v update-grub &>/dev/null || return 0
  detect_kernels

  if has_nv_module "$NEWEST_KERNEL"; then
    if grep -q '# driver-fix' /etc/default/grub 2>/dev/null; then
      run "Retour au noyau le plus récent par défaut" sed -i -E 's|^GRUB_DEFAULT=.*# driver-fix$|GRUB_DEFAULT=0|' /etc/default/grub
      run "Mise à jour de GRUB" update-grub
    fi
    return 0
  fi

  local k best=""
  for k in "${KERNELS[@]}"; do has_nv_module "$k" && best=$k; done
  if [[ -z $best ]]; then
    fail "Aucun noyau n'a de module NVIDIA fonctionnel"
    return 1
  fi
  warn "Le noyau par défaut ($NEWEST_KERNEL) n'a pas de pilote NVIDIA"
  ask "Démarrer par défaut sur $best (qui a le pilote) ?" o || return 0

  local cfg=/boot/grub/grub.cfg sub entry
  sub=$(sed -nE "s/^submenu .*menuentry_id_option '([^']+)'.*/\1/p" "$cfg" 2>/dev/null | head -n1)
  entry=$(sed -nE "s/.*menuentry_id_option '(gnulinux-${best//./\\.}-advanced-[^']+)'.*/\1/p" "$cfg" 2>/dev/null | head -n1)
  if [[ -z $sub || -z $entry ]]; then
    warn "Entrée GRUB introuvable : choisis $best dans « Options avancées » au démarrage"
    return 1
  fi
  run "Sauvegarde de /etc/default/grub" cp /etc/default/grub /etc/default/grub.driver-fix.bak
  run "Noyau par défaut → $best" sed -i -E "s|^#?[[:space:]]*GRUB_DEFAULT=.*|GRUB_DEFAULT=\"$sub>$entry\" # driver-fix|" /etc/default/grub
  run "Mise à jour de GRUB" update-grub && GRUB_PINNED=$best
}

debian_fix() {
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
  local k
  for k in "${KERNELS[@]}"; do
    pkg_available "linux-headers-$k" && run "En-têtes du noyau $k" apt_install "linux-headers-$k"
  done
  local meta
  meta=$(dpkg_installed 'linux-image-*' | grep -vE '^linux-image-[0-9]' | head -n1)
  [[ -n $meta ]] && run "En-têtes automatiques pour les futurs noyaux" apt_install "${meta/image/headers}"
  run "Installation du pilote nvidia-driver" apt_install nvidia-driver firmware-misc-nonfree || return 1
  USED_DKMS=1
  for k in "${KERNELS[@]}"; do
    has_nv_module "$k" || run "Compilation du module NVIDIA pour $k" dkms autoinstall -k "$k"
  done
}

fedora_fix() {
  if ! dnf repolist --enabled 2>/dev/null | grep -qi rpmfusion-nonfree; then
    local v
    v=$(rpm -E %fedora)
    run "Activation des dépôts RPM Fusion" dnf install -y \
      "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$v.noarch.rpm" \
      "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$v.noarch.rpm" || return 1
  fi
  run "Installation du pilote (akmod-nvidia)" dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda kernel-devel || return 1
  USED_DKMS=1
  local k
  for k in "${KERNELS[@]}"; do
    has_nv_module "$k" && continue
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
  local pkgs=(nvidia-open-dkms nvidia-utils dkms) kp
  for kp in linux linux-lts linux-zen linux-hardened linux-rt linux-rt-lts; do
    pacman -Q "$kp" &>/dev/null && pkgs+=("$kp-headers")
  done
  for kp in nvidia nvidia-open nvidia-lts nvidia-open-lts; do
    pacman -Q "$kp" &>/dev/null && run "Retrait de $kp (remplacé par la version DKMS)" pacman -Rdd --noconfirm "$kp"
  done
  run "Mise à jour du système + pilote nvidia-open-dkms" pacman -Syu --needed --noconfirm "${pkgs[@]}" || return 1
  USED_DKMS=1
  detect_kernels
  local k
  for k in "${KERNELS[@]}"; do
    has_nv_module "$k" || run "Compilation du module NVIDIA pour $k" dkms autoinstall -k "$k"
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
  if [[ $FAMILY == ubuntu || $FAMILY == debian ]] && ((!OPT_DIAGNOSE)); then
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
  local g name drv icon
  for g in "${GPU_LINES[@]}"; do
    name=${g%|*} drv=${g##*|}
    case $drv in
      nvidia | amdgpu | i915 | xe) icon="${GRN}●${R}" ;;
      nouveau | "aucun pilote") icon="${RED}●${R}" ;;
      *) icon="${YLW}●${R}" ;;
    esac
    printf '  %s %s%s%s\n' "$icon" "$B" "$name" "$R"
    note "pilote utilisé : $drv"
  done
  ((${#GPU_LINES[@]} == 0)) && warn "Aucune carte graphique trouvée sur le bus PCI"
  if ((HAS_NVIDIA)); then
    ((HAS_NVIDIA && HAS_OTHER_GPU)) && kv "Type" "portable hybride (iGPU + NVIDIA)"
    [[ -n $NV_DRIVER_VERSION ]] && kv "Pilote NVIDIA" "$NV_DRIVER_VERSION"
    ((NV_SMI_OK)) && kv "nvidia-smi" "${GRN}fonctionne${R}" || kv "nvidia-smi" "${RED}ne répond pas${R}"
    [[ -n $PRIME_MODE ]] && kv "Mode PRIME" "$PRIME_MODE"
  fi
}

show_diagnosis() {
  step "Diagnostic"
  local p
  for p in "${PROBLEMS[@]}"; do fail "$p"; done
  for p in "${WARNINGS[@]}"; do warn "$p"; done
  if ((${#PROBLEMS[@]} == 0 && ${#WARNINGS[@]} == 0)); then
    ok "Aucun problème détecté côté pilote 🎉"
  fi
}

apply_fixes() {
  step "Réparation"
  case $FAMILY in
    ubuntu) ubuntu_fix ;;
    debian) debian_fix ;;
    fedora) fedora_fix ;;
    arch) arch_fix ;;
  esac
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
  local k tag
  for k in "${KERNELS[@]}"; do
    tag=""
    [[ $k == "$RUNNING_KERNEL" ]] && tag+=" ${D}· actuel${R}"
    if [[ -n $GRUB_PINNED ]]; then
      [[ $k == "$GRUB_PINNED" ]] && tag+=" ${CYN}· démarrage par défaut${R}"
    elif [[ $k == "$NEWEST_KERNEL" ]]; then
      tag+=" ${CYN}· démarrage par défaut${R}"
    fi
    if has_nv_module "$k"; then
      printf '  %s✔%s %-26s pilote NVIDIA prêt%s\n' "$GRN" "$R" "$k" "$tag"
    else
      printf '  %s✖%s %-26s pas de pilote NVIDIA%s\n' "$RED" "$R" "$k" "$tag"
    fi
  done
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
      "  3. Tape le mot de passe choisi tout à l'heure" \
      "  4. « Reboot »" \
      "" \
      "${D}Si tu rates cet écran, relance simplement le script.${R}"
  fi

  local title="${GRN}${B}✔ C'est réparé !${R}"
  ((${#FAILED[@]})) && title="${YLW}${B}Réparation partielle appliquée${R}"
  box "$GRN" \
    "$title" \
    "" \
    "${B}➜ Redémarre ton PC${R} pour appliquer le fix," \
    "  puis branche ton câble HDMI." \
    "" \
    "${D}Toujours rien ? lance :  sudo prime-select nvidia${R}" \
    "${D}Aide : $REPO_URL${R}"

  if ((HAS_TTY && !OPT_YES)) && ask "Redémarrer maintenant ?" n; then
    info "Redémarrage dans 5 secondes… (Ctrl+C pour annuler)"
    sleep 5
    systemctl reboot
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
  -y, --yes           Répond « oui » à toutes les questions
  -p, --prime MODE    Force le mode PRIME : on-demand | nvidia | intel
      --no-color      Désactive les couleurs
  -h, --help          Affiche cette aide

Plus d'infos : $REPO_URL
EOF
}

parse_args() {
  while (($#)); do
    case $1 in
      -d | --diagnose) OPT_DIAGNOSE=1 ;;
      -n | --dry-run) OPT_DRY_RUN=1 ;;
      -y | --yes) OPT_YES=1 ;;
      -p | --prime)
        OPT_PRIME=${2:-}
        [[ $OPT_PRIME =~ ^(on-demand|nvidia|intel)$ ]] || { echo "Mode PRIME invalide : $OPT_PRIME" >&2; exit 1; }
        shift
        ;;
      --no-color) OPT_NO_COLOR=1 ;;
      -h | --help) usage; exit 0 ;;
      *) echo "Option inconnue : $1 (voir --help)" >&2; exit 1 ;;
    esac
    shift
  done
}

ensure_root() {
  [[ $EUID -eq 0 ]] && return 0
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

main() {
  parse_args "$@"
  setup_colors
  { : </dev/tty; } 2>/dev/null && HAS_TTY=1
  locale -a 2>/dev/null | grep -qiE '^c\.utf-?8$' && export LC_CTYPE=C.UTF-8

  ensure_root "$@"
  if [[ $EUID -eq 0 ]]; then LOG_FILE=/var/log/driver-fix.log; else LOG_FILE=${TMPDIR:-/tmp}/driver-fix-$USER.log; fi
  export DEBIAN_FRONTEND=noninteractive
  trap '((FANCY)) && printf "\e[?25h"' EXIT
  trap 'printf "\e[?25h\n"; warn "Interrompu."; exit 130' INT

  {
    printf '\n===== driver-fix v%s — %s =====\n' "$VERSION" "$(date '+%F %T')"
    uname -a
  } >>"$LOG_FILE" 2>/dev/null

  banner
  ((OPT_DRY_RUN)) && printf '  %sMode simulation : rien ne sera modifié%s\n' "$YLW" "$R"
  ((OPT_DIAGNOSE)) && printf '  %sMode diagnostic : rien ne sera modifié%s\n' "$YLW" "$R"

  detect_distro
  detect_kernels
  detect_gpus
  detect_secure_boot
  detect_driver_state
  analyze

  show_system
  show_gpus

  if ((!HAS_NVIDIA)); then
    no_nvidia
    exit 0
  fi

  show_diagnosis
  {
    printf 'Famille: %s | Noyaux: %s | Manquants: %s\n' "$FAMILY" "${KERNELS[*]}" "${MISSING_KERNELS[*]}"
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

  if ((${#PROBLEMS[@]} == 0)); then
    note "Le script peut quand même vérifier et sécuriser l'installation"
    note "(pilote installé pour tous les noyaux, futures mises à jour, etc.)."
    ask "Lancer la réparation préventive ?" n || { info "Rien à faire. Bonne journée !"; exit 0; }
  else
    ask "Lancer la réparation automatique ?" o || { info "Annulé, rien n'a été modifié."; exit 0; }
  fi

  apply_fixes
  verify
  final_message
}

main "$@"
