#!/bin/bash
# install.sh — one-shot installer for the MacBook8,1 (CS4208) built-in speaker fix.
#
# Installs, as a DKMS package that rebuilds on every kernel upgrade:
#   (A) snd-hda-intel     — no-reset attach to the live EFI link
#   (C) snd-hda-codec-cs420x — EFI coef image + TDM prepare sync-dance fix
#   (D) snd-hda-codec-generic — CS4208 input-path + init_digital skip (clock latch)
# plus the runtime config:
#   (B) mb81-singlecmd.conf  -> /etc/modprobe.d/   (single_cmd=1, reliable enum)
# The speaker names and the EQ chain are not this package. They are
# macbook81-audio-profile, installed per user, without root.
# plus the suspend/resume recovery (S3 resume re-latches the codec clock; a bound
# driver cannot clear it, so audio returns silent):
#       resume_recover.sh + efi_recover.py -> /usr/local/bin/
#       mb81-resume-recover.service -> /etc/systemd/system/ (runs on every resume)
#
# Run:  sudo bash install.sh
# Remove: sudo bash install.sh -r
set -eu

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

action='install'
[[ "${1:-}" == "-r" || "${1:-}" == "-u" || "${1:-}" == "--remove" ]] && action='remove'

[[ $EUID -ne 0 ]] && { echo "must be root: sudo bash $0 ${1:-}"; exit 1; }

if [[ $action == 'install' ]] && dkms status 2>/dev/null | grep -q '^macbook12-audio'; then
    echo "ERROR: macbook12-audio is installed. It ships the same three modules."
    echo "       Remove it before installing macbook81-cs4208. This script will not."
    exit 1
fi

# The invoking user, so the jack watcher is enabled on their session bus.
real_user="${SUDO_USER:-$USER}"
real_uid="$(id -u "$real_user")"

# Run `systemctl --user` as the invoking user, against their session bus.
user_systemctl() {
    sudo -u "$real_user" \
        XDG_RUNTIME_DIR="/run/user/$real_uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$real_uid/bus" \
        systemctl --user "$@"
}

# Rebuild the boot image. The patched modules and mb81-singlecmd.conf are
# baked into it. dkms install does not refresh it. On Omarchy that refresh
# is limine-mkinitcpio, not limine-update. update-initramfs is the other
# path. Skipping this leaves the next boot on the previous image.
refresh_initramfs() {
    echo "=== refreshing boot image (so new modules + softdep reach boot) ==="
    if command -v limine-mkinitcpio > /dev/null; then
        limine-mkinitcpio || exit 1
        return
    fi
    if command -v update-initramfs > /dev/null; then
        update-initramfs -u -k all || exit 1
        return
    fi
    echo "ERROR: neither limine-mkinitcpio nor update-initramfs is installed."
    echo "       The modules on disk will not be the ones used at boot."
    exit 1
}

if [[ $action == 'remove' ]]; then
    echo "=== removing suspend/resume recovery service ==="
    systemctl disable --now mb81-resume-recover.service 2>/dev/null || true
    rm -f /etc/systemd/system/mb81-resume-recover.service \
          /usr/local/bin/mb81-resume-recover /usr/local/bin/efi_recover.py
    systemctl daemon-reload 2>/dev/null || true
    echo "=== removing headphone jack-switch service ==="
    user_systemctl disable --now mb81-jack-switch.service 2>/dev/null || true
    rm -f /etc/systemd/user/mb81-jack-switch.service /usr/local/bin/mb81-jack-switch
    user_systemctl daemon-reload 2>/dev/null || true
    echo "=== removing DKMS package ==="
    # Defer the initramfs refresh: the modprobe.d conf is still on disk here,
    # and refreshing now would bake it back in. Done once at the end instead.
    MB81_SKIP_INITRAMFS=1 bash dkms.sh -r || true
    echo "=== removing config files ==="
    rm -f /etc/modprobe.d/mb81-singlecmd.conf
    # Speaker names and the EQ chain belong to macbook81-audio-profile.
    # Do not remove that user's files from this driver uninstall.
    depmod -a
    if [[ "${MB81_SKIP_INITRAMFS:-}" == "1" ]]; then
        echo "=== boot image refresh deferred ==="
    else
        refresh_initramfs
    fi
    echo "DONE. Reboot to fall back to the stock in-tree drivers."
    exit 0
fi

echo "=== (B) modprobe.d: single_cmd=1 ==="
install -m 0644 mb81-singlecmd.conf /etc/modprobe.d/mb81-singlecmd.conf

echo "=== headphone jack auto-switch (user service) ==="
install -m 0755 mb81-jack-switch.sh /usr/local/bin/mb81-jack-switch
install -m 0644 mb81-jack-switch.service /etc/systemd/user/mb81-jack-switch.service
if [[ -d "/run/user/$real_uid" ]]; then
    user_systemctl daemon-reload || true
    user_systemctl enable --now mb81-jack-switch.service || true
    echo "    jack-switch service enabled for $real_user"
else
    echo "    NOTE: no active session for $real_user; enable it after next login with:"
    echo "          systemctl --user enable --now mb81-jack-switch.service"
fi

echo "=== suspend/resume recovery (re-heals the codec clock latch on every wake) ==="
install -m 0755 resume_recover.sh /usr/local/bin/mb81-resume-recover
# efi_recover.py is invoked from the same dir as the script; keep them co-located.
install -m 0755 efi_recover.py /usr/local/bin/efi_recover.py
install -m 0644 mb81-resume-recover.service /etc/systemd/system/mb81-resume-recover.service
systemctl daemon-reload || true
systemctl enable mb81-resume-recover.service || true
echo "    mb81-resume-recover.service enabled (runs on every resume)"

echo "=== clearing stale standalone module copies (so DKMS's updates/dkms wins) ==="
# Earlier manual install.*.driver.sh runs put these directly in updates/, which
# would shadow the DKMS-managed copies in updates/dkms/. Remove them; DKMS
# reinstalls all three under updates/dkms/.
for kdir in /lib/modules/*/updates; do
    rm -f "$kdir"/snd-hda-codec-cs420x.ko* \
          "$kdir"/snd-hda-codec-generic.ko* \
          "$kdir"/snd-hda-intel.ko* 2>/dev/null || true
done

echo "=== (A/C/D) building + installing the three modules via DKMS ==="
# Defer dkms.sh's own refresh. This script rebuilds once below, unless
# the caller set MB81_SKIP_INITRAMFS=1 to batch that rebuild.
MB81_SKIP_INITRAMFS=1 bash dkms.sh
depmod -a

# Confirm before the boot image. A direct run must not refresh it
# unless dkms status says installed for the running kernel.
# shellcheck disable=SC1091
source "$here/kernel-src.sh"
require_installed "macbook81-cs4208/0.1" "$(uname -r)" || exit 1

if [[ "${MB81_SKIP_INITRAMFS:-}" == "1" ]]; then
    echo "=== boot image refresh deferred ==="
else
    refresh_initramfs
fi

echo
echo "================================================================"
echo "DONE. The patched snd-hda-intel autoloads at a normal boot and"
echo "attaches to the live EFI link without reset; CS4208 enumerates"
echo "via single_cmd. Speaker names and the EQ chain are a separate"
echo "package, macbook81-audio-profile. Reboot to activate."
echo "================================================================"
