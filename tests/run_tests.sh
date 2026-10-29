#!/usr/bin/env bash

set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT=${DRIVER_FIX_SCRIPT:-$HERE/../fix.sh}
BASH_REAL=$(command -v bash)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FILTER=${1:-}

PASS=0 FAILS=0 CUR="" T="" FAKE="" FR="" OUT="" RC=0
K=7.0.0-42-generic
REAL_TOOLS=(bash cat sed awk grep sort tail head cut tr od basename dirname readlink mkdir rm mv cp
  date sleep timeout env ls wc find mktemp tee touch uniq chmod)
MISC_STUBS=(uname lspci nvidia-smi journalctl dmesg ubuntu-drivers dkms mokutil prime-select df flock
  update-initramfs update-grub systemctl sudo)

scenario() {
  CUR=$1
  T=$WORK/$CUR FAKE=$T/fake FR=$T/root
  mkdir -p "$FAKE/effects" "$FAKE/mod" "$T/bin" "$T/sysbin"
  local t s
  for t in "${REAL_TOOLS[@]}"; do
    printf '#!%s\nexec %s "$@"\n' "$BASH_REAL" "$(command -v "$t")" >"$T/sysbin/$t"
  done
  for s in apt-get apt-cache dpkg dpkg-query modinfo; do cp "$HERE/stubs/$s" "$T/bin/$s"; done
  for s in "${MISC_STUBS[@]}"; do cp "$HERE/stubs/misc" "$T/bin/$s"; done
  chmod +x "$T"/bin/* "$T"/sysbin/*
  : >"$FAKE/calls"; : >"$FAKE/installed"; : >"$FAKE/available"
  echo "$K" >"$FAKE/kernel"
  echo on-demand >"$FAKE/prime"

  mkdir -p "$FR/etc" "$FR/lib/modules/$K" "$FR/boot" "$FR/sys/firmware/efi" "$FR/sys/module" \
    "$FR/proc/sys/kernel/random" "$FR/sys/bus/pci/devices"
  : >"$FR/boot/vmlinuz-$K"
  echo "11111111-aaaa-bbbb-cccc-000000000001" >"$FR/proc/sys/kernel/random/boot_id"
  cat >"$FR/etc/os-release" <<'EOF'
PRETTY_NAME="Ubuntu 26.04 LTS"
NAME="Ubuntu"
VERSION_ID="26.04"
VERSION="26.04 LTS (Resolute Raccoon)"
ID=ubuntu
ID_LIKE=debian
EOF
  add_gpu 0000:05:00.0 0x1002 0x1681 "Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt"
}

add_gpu() {
  local d=$FR/sys/bus/pci/devices/$1
  mkdir -p "$d"
  echo 0x030000 >"$d/class"; echo "$2" >"$d/vendor"; echo "$3" >"$d/device"
  echo "$1|$4" >>"$FAKE/lspci"
}

add_rtx5060() { add_gpu 0000:01:00.0 0x10de 0x2d59 "NVIDIA Corporation GB206M [GeForce RTX 5060 Max-Q / Mobile]"; }

installed() { printf '%s\n' "$@" >>"$FAKE/installed"; }
available() { printf '%s\n' "$@" >>"$FAKE/available"; }
remove_stub() { rm -f "$T/bin/$1"; }

set_module() {
  local d=$FAKE/mod/$K
  mkdir -p "$d"
  echo "$1" >"$d/license"; echo "$2" >"$d/version"; echo "$3" >"$d/filename"
  if [[ -n ${4:-} ]]; then echo "$4" >"$d/signer"; else rm -f "$d/signer"; fi
}

set_loaded() {
  mkdir -p "$FR/sys/module/nvidia" "$FR/sys/module/nvidia_drm/parameters" "$FR/proc/driver/nvidia"
  echo "$2" >"$FR/sys/module/nvidia/version"
  echo Y >"$FR/sys/module/nvidia_drm/parameters/modeset"
  if [[ $1 == open ]]; then
    echo "NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  $2  Release Build" >"$FR/proc/driver/nvidia/version"
  else
    echo "NVRM version: NVIDIA UNIX x86_64 Kernel Module  $2  Release Build" >"$FR/proc/driver/nvidia/version"
  fi
}

nvsmi() { printf '%s\n' "$1" >"$FAKE/nvsmi_out"; echo "$2" >"$FAKE/nvsmi_rc"; }
nvsmi_ok() { nvsmi "GPU 0: NVIDIA GeForce RTX 5060 Laptop GPU (UUID: GPU-0000)" 0; }
nvsmi_nodev() { nvsmi "No devices were found" 6; }
add_firmware() { mkdir -p "$FR/lib/firmware/nvidia/$1"; : >"$FR/lib/firmware/nvidia/$1/gsp_ga10x.bin"; }

klog_open_required() {
  cat >>"$FAKE/klog" <<'EOF'
NVRM: The NVIDIA GPU 0000:01:00.0 (PCI ID: 10de:2d59)
NVRM: installed in this system requires use of the NVIDIA open kernel modules.
NVRM: GPU 0000:01:00.0: RmInitAdapter failed! (0x22:0x56:1017)
NVRM: GPU 0000:01:00.0: rm_init_adapter failed, device minor number 0
EOF
}

ubuntu_drivers_595() {
  cat >"$FAKE/ubuntu_drivers" <<'EOF'
== /sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0 ==
modalias : pci:v000010DEd00002D59sv000017AAsd00003E50bc03sc00i00
vendor   : NVIDIA Corporation
driver   : nvidia-driver-580-open - distro non-free
driver   : nvidia-driver-595 - distro non-free
driver   : nvidia-driver-595-open - distro non-free recommended
driver   : nvidia-driver-580 - distro non-free
driver   : xserver-xorg-video-nouveau - distro free builtin
EOF
  available nvidia-driver-580-open nvidia-driver-580 nvidia-driver-595 nvidia-driver-595-open \
    "linux-modules-nvidia-595-open-$K" linux-modules-nvidia-595-open-generic "linux-headers-$K" \
    nvidia-dkms-595-open nvidia-utils-595
}

effect_open_prebuilt() {
  cat >"$FAKE/effects/linux-modules-nvidia-595-open-$K" <<EOF
d=\$FAKE/mod/$K; mkdir -p "\$d"
echo "Dual MIT/GPL" >"\$d/license"; echo 595.99.02 >"\$d/version"
echo /lib/modules/$K/kernel/nvidia-595-open/nvidia.ko >"\$d/filename"
echo "Canonical Ltd. Kernel Module Signing" >"\$d/signer"
EOF
}

effect_remove_module() { printf 'rm -rf "$FAKE/mod/%s"\n' "$K" >"$FAKE/effects/remove-$1"; }

setup_blackwell_proprietary() {
  add_rtx5060
  installed nvidia-driver-595 "linux-modules-nvidia-595-$K" linux-modules-nvidia-595-generic nvidia-utils-595 linux-image-generic
  set_module NVIDIA 595.99.02 "/lib/modules/$K/kernel/nvidia-595/nvidia.ko" "Canonical Ltd. Kernel Module Signing"
  set_loaded proprietary 595.99.02
  klog_open_required
  nvsmi_nodev
  ubuntu_drivers_595
  printf 'Remv nvidia-driver-595 [595.99.02]\nRemv libnvidia-gl-595 [595.99.02]\n' >"$FAKE/apt_sim"
  effect_open_prebuilt
  effect_remove_module "linux-modules-nvidia-595-$K"
}

run_fix() {
  OUT=$(cd "$T" && env -i PATH="$T/bin:$T/sysbin" HOME="$T" TERM=dumb \
    DRIVER_FIX_ROOT="$FR" DRIVER_FIX_TEST=1 DRIVER_FIX_LOG="$T/driver-fix.log" FAKE="$FAKE" \
    "$BASH_REAL" "$SCRIPT" --no-color "$@" 2>&1)
  RC=$?
}

ok_() { PASS=$((PASS + 1)); }
ko_() {
  FAILS=$((FAILS + 1))
  printf '  ✖ [%s] %s\n' "$CUR" "$1"
  [[ -n ${VERBOSE:-} ]] && { printf '%s\n' "--- sortie ---" "$OUT" "--- appels ---"; cat "$FAKE/calls"; }
}
expect_out() { grep -qF -- "$1" <<<"$OUT" && ok_ || ko_ "sortie attendue : $1"; }
refute_out() { grep -qF -- "$1" <<<"$OUT" && ko_ "sortie interdite : $1" || ok_; }
expect_call() { grep -qE -- "$1" "$FAKE/calls" && ok_ || ko_ "appel attendu : $1"; }
refute_call() { grep -qE -- "$1" "$FAKE/calls" && ko_ "appel interdit : $1" || ok_; }
expect_rc() { [[ $RC == "$1" ]] && ok_ || ko_ "code retour $RC au lieu de $1"; }
expect_rc_nonzero() { [[ $RC != 0 ]] && ok_ || ko_ "code retour 0 inattendu"; }
expect_file() { [[ -e $1 ]] && ok_ || ko_ "fichier attendu : ${1#"$FR"}"; }
refute_file() { [[ -e $1 ]] && ko_ "fichier interdit : ${1#"$FR"}" || ok_; }
no_crash() {
  refute_out "command not found"
  refute_out "unbound variable"
  refute_out "bad array subscript"
  refute_out "syntax error"
}
safety() {
  refute_call "purge"
  refute_call "systemctl reboot"
  refute_call "^sudo"
  refute_call "pacman -Rdd"
}

want() { [[ -z $FILTER || $1 == *$FILTER* ]]; }

t_blackwell_proprietary_diagnose() {
  scenario blackwell_proprietary_diagnose
  setup_blackwell_proprietary
  run_fix --diagnose
  expect_rc 0
  expect_out "exige les modules NVIDIA open (confirmé par les logs)"
  expect_out "RmInitAdapter failed (0x22:0x56:1017)"
  expect_out "Le paquet nvidia-driver-595 installe la variante propriétaire"
  expect_out "Le module installé pour $K est propriétaire"
  expect_out "linux-modules-nvidia-595-$K"
  expect_out "Cause identifiée : module propriétaire chargé"
  expect_out "No devices were found"
  refute_call "^apt-get"
  no_crash; safety
}

t_blackwell_proprietary_fix() {
  scenario blackwell_proprietary_fix
  setup_blackwell_proprietary
  run_fix --yes
  expect_call "apt-get -s .*install nvidia-driver-595-open"
  expect_call "apt-get .* install -y nvidia-driver-595-open$"
  expect_call "apt-get .* remove -y linux-modules-nvidia-595-$K linux-modules-nvidia-595-generic$"
  expect_call "install -y linux-modules-nvidia-595-open-$K$"
  expect_call "install -y linux-modules-nvidia-595-open-generic$"
  expect_call "update-initramfs -u -k all"
  expect_out "Remplacement prévu : nvidia-driver-595 → nvidia-driver-595-open"
  expect_out "module open (Dual MIT/GPL)"
  expect_out "Correctif installé — redémarrage nécessaire"
  refute_out "C'est réparé"
  refute_out "fonctionne déjà"
  expect_file "$FR/etc/modprobe.d/driver-fix-nvidia.conf"
  expect_file "$FR/var/lib/driver-fix/last-run"
  grep -q "annuler : sudo apt-get install nvidia-driver-595" "$FR/var/lib/driver-fix/history.log" 2>/dev/null &&
    ok_ || ko_ "historique sans commande de retour arrière"
  expect_rc 0
  no_crash; safety
}

t_blackwell_dry_run() {
  scenario blackwell_dry_run
  setup_blackwell_proprietary
  run_fix --dry-run --yes
  expect_out "simulation : apt_install nvidia-driver-595-open"
  refute_call "apt-get .* install -y"
  refute_call "remove -y"
  refute_call "update-initramfs"
  refute_file "$FR/etc/modprobe.d/driver-fix-nvidia.conf"
  refute_file "$FR/var/lib/driver-fix/history.log"
  no_crash; safety
}

t_open_on_disk_proprietary_loaded() {
  scenario open_on_disk_proprietary_loaded
  add_rtx5060
  installed nvidia-driver-595-open nvidia-dkms-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/updates/dkms/nvidia.ko.zst"
  set_loaded proprietary 595.99.02
  add_firmware 595.99.02
  klog_open_required
  nvsmi_nodev
  run_fix --diagnose
  expect_out "le bon module (open) est déjà sur le disque : il faut redémarrer"
  refute_out "installe la variante propriétaire"
  refute_out "Le module installé pour"
  no_crash; safety
}

t_open_driver_with_proprietary_leftover() {
  scenario open_driver_with_proprietary_leftover
  add_rtx5060
  installed nvidia-driver-595-open "linux-modules-nvidia-595-$K" nvidia-utils-595
  set_module NVIDIA 595.99.02 "/lib/modules/$K/kernel/nvidia-595/nvidia.ko" "Canonical Ltd. Kernel Module Signing"
  set_loaded proprietary 595.99.02
  klog_open_required
  nvsmi_nodev
  ubuntu_drivers_595
  effect_open_prebuilt
  effect_remove_module "linux-modules-nvidia-595-$K"
  run_fix --yes
  expect_out "Pilote déjà installé et adapté : nvidia-driver-595-open"
  refute_call "install -y nvidia-driver-595-open$"
  expect_call "remove -y linux-modules-nvidia-595-$K$"
  expect_call "install -y linux-modules-nvidia-595-open-$K$"
  expect_out "redémarrage nécessaire"
  no_crash; safety
}

t_dkms_still_wrong_flavor() {
  scenario dkms_still_wrong_flavor
  add_rtx5060
  installed nvidia-driver-595-open nvidia-utils-595
  set_module NVIDIA 595.99.02 "/lib/modules/$K/updates/dkms/nvidia.ko"
  available nvidia-driver-595-open "linux-headers-$K" nvidia-dkms-595-open
  printf 'driver   : nvidia-driver-595-open - distro non-free recommended\n' >"$FAKE/ubuntu_drivers"
  run_fix --yes
  expect_call "install -y linux-headers-$K$"
  expect_call "install -y nvidia-dkms-595-open$"
  expect_call "dkms autoinstall -k $K"
  expect_out "le module de $K est toujours propriétaire"
  expect_out "compilé par DKMS"
  expect_out "Réparation partielle appliquée"
  expect_out "« nouveau » reste actif"
  refute_file "$FR/etc/modprobe.d/driver-fix-nouveau.conf"
  expect_rc_nonzero
  no_crash; safety
}

t_open_working() {
  scenario open_working
  add_rtx5060
  installed nvidia-driver-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/kernel/nvidia-595-open/nvidia.ko" "Canonical Ltd. Kernel Module Signing"
  set_loaded open 595.99.02
  add_firmware 595.99.02
  echo "NVRM: loading NVIDIA UNIX Open Kernel Module for x86_64  595.99.02" >"$FAKE/klog"
  nvsmi_ok
  run_fix --diagnose
  expect_out "Aucun problème détecté"
  expect_out "fonctionne"
  run_fix
  expect_out "Rien à réparer"
  refute_call "^apt-get"
  expect_rc 0
  run_fix --interactive
  expect_out "Rien à faire"
  refute_call "^apt-get"
  no_crash; safety
}

t_default_is_automatic() {
  scenario default_is_automatic
  setup_blackwell_proprietary
  run_fix
  expect_call "install -y nvidia-driver-595-open$"
  expect_call "install -y linux-modules-nvidia-595-open-$K$"
  refute_out "[O/n]"
  refute_out "[o/N]"
  expect_out "Redémarre ton PC pour terminer"
  refute_out "vérifie avec"
  refute_call "systemctl reboot"
  expect_rc 0
  no_crash; safety
}

t_no_driver() {
  scenario no_driver
  add_rtx5060
  mkdir -p "$FR/sys/module/nouveau"
  remove_stub nvidia-smi
  installed linux-image-generic
  ubuntu_drivers_595
  effect_open_prebuilt
  run_fix --diagnose
  expect_out "Aucun pilote NVIDIA n'est installé"
  expect_out "déduit de l'ID PCI"
  expect_out "« nouveau » est utilisé"
  run_fix --yes
  expect_out "Pilote choisi par ubuntu-drivers pour ce GPU : nvidia-driver-595-open"
  expect_call "install -y nvidia-driver-595-open$"
  expect_call "install -y linux-modules-nvidia-595-open-$K$"
  expect_call "install -y nvidia-utils-595$"
  expect_file "$FR/etc/modprobe.d/driver-fix-nouveau.conf"
  expect_out "redémarrage nécessaire"
  no_crash; safety
}

t_amd_only() {
  scenario amd_only
  remove_stub nvidia-smi
  run_fix --diagnose
  expect_rc 0
  expect_out "Aucune carte NVIDIA détectée"
  refute_out "Diagnostic"
  refute_call "^apt-get"
  no_crash; safety
}

t_ada_proprietary_not_forced_open() {
  scenario ada_proprietary_not_forced_open
  add_gpu 0000:01:00.0 0x10de 0x28e0 "NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q / Mobile]"
  installed nvidia-driver-580 nvidia-utils-580
  set_module NVIDIA 580.95.05 "/lib/modules/$K/kernel/nvidia-580/nvidia.ko" "Canonical Ltd. Kernel Module Signing"
  set_loaded proprietary 580.95.05
  nvsmi "GPU 0: NVIDIA GeForce RTX 4060 Laptop GPU (UUID: GPU-1)" 0
  run_fix --diagnose
  expect_out "Aucun problème détecté"
  refute_out "exige"
  no_crash; safety
}

t_nvidia_smi_absent() {
  scenario nvidia_smi_absent
  add_rtx5060
  installed nvidia-driver-595-open
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/kernel/nvidia-595-open/nvidia.ko" "Canonical"
  set_loaded open 595.99.02
  add_firmware 595.99.02
  remove_stub nvidia-smi
  run_fix --diagnose
  expect_out "nvidia-smi est absent"
  no_crash; safety
}

t_nvidia_smi_fails() {
  scenario nvidia_smi_fails
  add_rtx5060
  installed nvidia-driver-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/kernel/nvidia-595-open/nvidia.ko" "Canonical"
  set_loaded open 595.99.02
  add_firmware 595.99.02
  nvsmi "NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver." 9
  run_fix --diagnose
  expect_out "nvidia-smi échoue : NVIDIA-SMI has failed"
  no_crash; safety
}

t_secure_boot_rejected() {
  scenario secure_boot_rejected
  add_rtx5060
  echo "SecureBoot enabled" >"$FAKE/sb_state"
  installed nvidia-driver-595-open nvidia-dkms-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/updates/dkms/nvidia.ko"
  echo "Loading of module with unavailable key is rejected" >"$FAKE/klog"
  mkdir -p "$FR/var/lib/shim-signed/mok"; : >"$FR/var/lib/shim-signed/mok/MOK.der"
  add_firmware 595.99.02
  nvsmi "NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver." 9
  available nvidia-driver-595-open
  run_fix --diagnose
  expect_out "Secure Boot      activé"
  expect_out "Secure Boot refuse de charger le module NVIDIA"
  expect_out "non signé"
  refute_out "désactive Secure Boot"
  run_fix
  expect_call "mokutil --generate-hash=[0-9]{8}$"
  expect_call "mokutil --import .*MOK.der --hash-file "
  expect_out "Enroll MOK"
  local pw
  pw=$(grep -oE 'generate-hash=[0-9]{8}' "$FAKE/calls" | head -n1 | cut -d= -f2)
  expect_out "Tape le mot de passe : $pw"
  [[ $(cat "$FR/var/lib/driver-fix/mok-password" 2>/dev/null) == "$pw" ]] && ok_ || ko_ "mot de passe MOK non sauvegardé"
  refute_out "Réparation partielle appliquée"
  refute_out "désactive Secure Boot"
  expect_rc 0
  no_crash; safety
}

t_secure_boot_old_mokutil_no_tty() {
  scenario secure_boot_old_mokutil_no_tty
  add_rtx5060
  echo "SecureBoot enabled" >"$FAKE/sb_state"
  : >"$FAKE/mok_old"
  installed nvidia-driver-595-open nvidia-dkms-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/updates/dkms/nvidia.ko"
  echo "Loading of module with unavailable key is rejected" >"$FAKE/klog"
  mkdir -p "$FR/var/lib/shim-signed/mok"; : >"$FR/var/lib/shim-signed/mok/MOK.der"
  add_firmware 595.99.02
  available nvidia-driver-595-open
  run_fix
  expect_out "À faire à la main : sudo mokutil --import"
  refute_call "mokutil --import"
  expect_out "Réparation partielle appliquée"
  expect_rc_nonzero
  no_crash; safety
}

t_apt_unavailable() {
  scenario apt_unavailable
  setup_blackwell_proprietary
  remove_stub apt-get
  remove_stub apt-cache
  run_fix --yes
  expect_out "APT est indisponible"
  expect_out "Réparation partielle appliquée"
  refute_out "Correctif installé"
  expect_rc_nonzero
  no_crash; safety
}

t_apt_install_fails() {
  scenario apt_install_fails
  setup_blackwell_proprietary
  : >"$FAKE/apt_fail"
  run_fix --yes
  expect_out "Installation du pilote nvidia-driver-595-open (erreur 100)"
  expect_out "Réparation partielle appliquée"
  refute_call "remove -y"
  refute_file "$FR/etc/modprobe.d/driver-fix-nouveau.conf"
  expect_rc_nonzero
  no_crash; safety
}

t_apt_conflict() {
  scenario apt_conflict
  setup_blackwell_proprietary
  echo 100 >"$FAKE/apt_sim_rc"
  run_fix --yes
  expect_out "APT refuse l'opération"
  refute_call "install -y nvidia-driver-595-open"
  expect_rc_nonzero
  no_crash; safety
}

t_unsafe_removal_refused() {
  scenario unsafe_removal_refused
  setup_blackwell_proprietary
  echo "Remv ubuntu-desktop [1.0]" >>"$FAKE/apt_sim"
  run_fix --yes
  expect_out "APT voulait aussi retirer ubuntu-desktop"
  refute_call "install -y nvidia-driver-595-open"
  expect_rc_nonzero
  no_crash; safety
}

t_gsp_firmware_missing() {
  scenario gsp_firmware_missing
  add_rtx5060
  installed nvidia-driver-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/kernel/nvidia-595-open/nvidia.ko" "Canonical"
  set_loaded open 595.99.02
  printf '%s\n' "NVRM: GPU 0000:01:00.0: Failed to load GSP firmware" \
    "NVRM: GPU 0000:01:00.0: RmInitAdapter failed! (0x62:0x40:1868)" >"$FAKE/klog"
  nvsmi_nodev
  run_fix --diagnose
  expect_out "Firmware GSP NVIDIA introuvable pour la version 595.99.02"
  expect_out "Erreur du firmware GSP"
  expect_out "RmInitAdapter sans cause évidente"
  expect_out "--reinstall nvidia-driver-595-open"
  no_crash; safety
}

t_rebooted_still_failing() {
  scenario rebooted_still_failing
  add_rtx5060
  installed nvidia-driver-595-open nvidia-utils-595
  set_module "Dual MIT/GPL" 595.99.02 "/lib/modules/$K/kernel/nvidia-595-open/nvidia.ko" "Canonical"
  set_loaded open 595.99.02
  add_firmware 595.99.02
  nvsmi_nodev
  mkdir -p "$FR/var/lib/driver-fix"
  printf 'boot_id=ancien-boot\ndate=2026-10-28 10:00:00\n' >"$FR/var/lib/driver-fix/last-run"
  run_fix --diagnose
  expect_out "Le PC a redémarré depuis la dernière réparation (2026-10-28 10:00:00)"
  no_crash; safety
}

t_low_boot_space() {
  scenario low_boot_space
  add_rtx5060
  echo 50000 >"$FAKE/boot_free"
  run_fix --diagnose
  expect_out "Peu d'espace libre dans /boot"
  no_crash; safety
}

t_undo() {
  scenario undo
  mkdir -p "$FR/etc/modprobe.d" "$FR/etc/default"
  echo "blacklist nouveau" >"$FR/etc/modprobe.d/driver-fix-nouveau.conf"
  echo "options nvidia-drm modeset=1" >"$FR/etc/modprobe.d/driver-fix-nvidia.conf"
  echo "GRUB_DEFAULT=0" >"$FR/etc/default/grub.driver-fix.bak"
  echo 'GRUB_DEFAULT="x>y" # driver-fix' >"$FR/etc/default/grub"
  echo "keep" >"$FR/etc/modprobe.d/autre.conf"
  run_fix --undo --yes
  refute_file "$FR/etc/modprobe.d/driver-fix-nouveau.conf"
  refute_file "$FR/etc/modprobe.d/driver-fix-nvidia.conf"
  expect_file "$FR/etc/modprobe.d/autre.conf"
  [[ $(cat "$FR/etc/default/grub") == "GRUB_DEFAULT=0" ]] && ok_ || ko_ "GRUB non restauré"
  expect_call "update-grub"
  expect_call "update-initramfs -u -k all"
  refute_call "^apt-get"
  expect_rc 0
  no_crash; safety
}

t_os_release_does_not_clobber_version() {
  scenario os_release_version
  run_fix --help
  expect_out "driver-fix v2."
  refute_out "Resolute"
}

t_unit_functions() {
  scenario unit
  OUT=$(env -i PATH="$T/bin:$T/sysbin" FAKE="$FAKE" DRIVER_FIX_SOURCED=1 "$BASH_REAL" -c '
    source "$1"
    for p in nvidia-driver-595 nvidia-driver-595-open nvidia-driver-595-server-open \
             linux-modules-nvidia-595-open-generic linux-modules-nvidia-595-7.0.0-42-generic nvidia-dkms-595; do
      echo "$p=$(pkg_flavor "$p")"
    done
    mkdir -p "$FAKE/mod/k1"; echo "Dual MIT/GPL" >"$FAKE/mod/k1/license"
    mkdir -p "$FAKE/mod/k2"; echo "NVIDIA" >"$FAKE/mod/k2/license"
    echo "k1=$(nv_mod_flavor k1) k2=$(nv_mod_flavor k2) k3=$(nv_mod_flavor k3)"
  ' _ "$SCRIPT" 2>&1)
  expect_out "nvidia-driver-595=proprietary"
  expect_out "nvidia-driver-595-open=open"
  expect_out "nvidia-driver-595-server-open=open"
  expect_out "linux-modules-nvidia-595-open-generic=open"
  expect_out "linux-modules-nvidia-595-7.0.0-42-generic=proprietary"
  expect_out "nvidia-dkms-595=proprietary"
  expect_out "k1=open k2=proprietary k3=none"
}

TESTS=$(declare -F | awk '$3 ~ /^t_/ {print $3}')
for t in $TESTS; do
  want "$t" || continue
  before=$FAILS
  "$t"
  ((FAILS == before)) && printf '  ✔ %s\n' "${t#t_}"
done
printf '\n%d vérifications réussies, %d échouées\n' "$PASS" "$FAILS"
((FAILS == 0))
