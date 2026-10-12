#!/bin/bash
# Fetch the matching kernel tarball. The installed headers tree is the
# compile target. It does not contain the codec sources.

fetch_mainline() {
    local build_dir=$1 version=$2 short=$3 major=$4
    local tool url archive topdir
    if command -v wget >/dev/null 2>&1; then
        tool=wget
    elif command -v curl >/dev/null 2>&1; then
        tool=curl
    else
        echo "neither wget nor curl is installed. This is not a missing tarball." >&2
        return 2
    fi
    mkdir -p "$build_dir"
    url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${version}.tar.xz"
    archive="$build_dir/linux-${version}.tar.xz"
    topdir="linux-${version}"
    if ! _fetch "$tool" "$url" "$build_dir"; then
        url="https://cdn.kernel.org/pub/linux/kernel/v${major}.x/linux-${short}.tar.xz"
        archive="$build_dir/linux-${short}.tar.xz"
        topdir="linux-${short}"
        if ! _fetch "$tool" "$url" "$build_dir"; then
            echo "could not fetch linux-${version} or linux-${short}" >&2
            return 1
        fi
    fi
    printf '%s\n%s\n' "$archive" "$topdir"
}

_fetch() {
    local tool=$1 url=$2 dest=$3
    if [[ $tool == wget ]]; then
        wget -c "$url" -P "$dest"
        return
    fi
    curl -fL --retry 2 -o "$dest/$(basename "$url")" "$url"
}

# 0: archive path and top dir on stdout.
# 1: no downloader, or the download failed and apt-get is absent.
# 3: the download failed and apt-get exists. The caller may try the
#    Ubuntu linux-source package. This function does not run apt-get.
resolve_kernel_src() {
    local out rc errexit=0
    [[ $- == *e* ]] && errexit=1
    set +e
    out=$(fetch_mainline "$@")
    rc=$?
    [[ $errexit -eq 1 ]] && set -e
    if [[ $rc -eq 0 ]]; then
        printf '%s\n' "$out"
        return 0
    fi
    if [[ $rc -ne 2 ]] && command -v apt-get >/dev/null 2>&1; then
        return 3
    fi
    if [[ $rc -eq 2 ]]; then
        return 1
    fi
    echo "could not fetch linux-$2. The download failed, and apt-get is not installed." >&2
    return 1
}

require_installed() {
    local spec=$1 kernel=$2
    local text
    text=$(dkms status 2>/dev/null || true)
    if printf '%s\n' "$text" | grep -F "${spec}, ${kernel}," | grep -q ': installed'; then
        return 0
    fi
    echo "${spec} is not installed for ${kernel}" >&2
    if [[ -n ${text} ]]; then
        printf '%s\n' "$text" >&2
    else
        echo "dkms status is empty" >&2
    fi
    return 1
}
