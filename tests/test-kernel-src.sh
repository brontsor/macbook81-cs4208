#!/bin/bash
# The codec sources are not in the installed headers tree. A missing wget
# is not "kernel.org has no tarball", and apt-get is not the fallback on
# a machine that does not have it.
set -eu
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f kernel-src.sh ]] || fail "kernel-src.sh is missing"
if grep -q 'kernel.org has no' install.cirrus.driver.sh kernel-src.sh; then
    fail "still claims kernel.org has no tarball"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/build" "$tmp/core" "$tmp/empty"
for cmd in mkdir basename dirname grep printf sed touch chmod; do
    ln -s "$(command -v "$cmd")" "$tmp/core/$cmd"
done
path_of() { printf '%s:%s' "$1" "$tmp/core"; }

# curl present, wget absent: fetch the versioned tarball, do not call apt-get.
mkdir -p "$tmp/bin" "$tmp/build"
cat > "$tmp/bin/curl" << 'EOF'
#!/bin/bash
out=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -o) out=$2; shift 2;;
        *) shift;;
    esac
done
mkdir -p "$(dirname "$out")"
echo "fake" > "$out"
exit 0
EOF
chmod +x "$tmp/bin/curl"
cat > "$tmp/bin/apt-get" << EOF
#!/bin/bash
touch "$tmp/apt-ran"
echo "apt-get should not run" >&2
exit 99
EOF
chmod +x "$tmp/bin/apt-get"

# shellcheck disable=SC1091
source ./kernel-src.sh
out=$(PATH="$(path_of "$tmp/bin")" fetch_mainline "$tmp/build" 7.2.8 7.2 7)
archive=$(printf '%s\n' "$out" | sed -n '1p')
topdir=$(printf '%s\n' "$out" | sed -n '2p')
[[ $archive == "$tmp/build/linux-7.2.8.tar.xz" ]] || fail "archive is $archive"
[[ $topdir == linux-7.2.8 ]] || fail "topdir is $topdir"
[[ -f $archive ]] || fail "curl did not write the archive"

# Neither downloader: say so, and do not claim the tarball is absent.
set +e
err=$(PATH="$(path_of "$tmp/empty")" fetch_mainline "$tmp/build" 7.2.8 7.2 7 2>&1)
rc=$?
set -e
mkdir -p "$tmp/empty"
[[ $rc -eq 2 ]] || fail "missing downloader returned $rc"
printf '%s\n' "$err" | grep -q 'neither wget nor curl' || fail "missing-downloader message: $err"
printf '%s\n' "$err" | grep -q 'kernel.org has no' && fail "missing wget was called a missing tarball"

# Download failed, apt-get absent: do not fall through to apt-get.
cat > "$tmp/bin/curl" << 'EOF'
#!/bin/bash
exit 22
EOF
chmod +x "$tmp/bin/curl"
mkdir -p "$tmp/noapt"
cp "$tmp/bin/curl" "$tmp/noapt/curl"
set +e
err=$(PATH="$(path_of "$tmp/noapt")" resolve_kernel_src "$tmp/build" 7.2.8 7.2 7 2>&1)
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "failed download without apt-get returned $rc"
printf '%s\n' "$err" | grep -q 'apt-get is not installed' || fail "no-apt message: $err"
printf '%s\n' "$err" | grep -q 'kernel.org has no' && fail "download failure was called a missing tarball"

# Download failed, apt-get present: signal the Ubuntu fallback. Do not claim
# the tarball is absent, and do not run apt-get from this function.
set +e
err=$(PATH="$(path_of "$tmp/bin")" resolve_kernel_src "$tmp/build" 7.2.8 7.2 7 2>&1)
rc=$?
set -e
[[ $rc -eq 3 ]] || fail "apt present returned $rc: $err"
printf '%s\n' "$err" | grep -q 'kernel.org has no' && fail "apt fallback claimed the tarball is absent"
[[ ! -f $tmp/apt-ran ]] || fail "resolve_kernel_src ran apt-get"

# added is not installed. installed for another kernel is not installed.
cat > "$tmp/bin/dkms" << 'EOF'
#!/bin/bash
printf '%s\n' "macbook81-cs4208/0.1: added"
exit 0
EOF
chmod +x "$tmp/bin/dkms"
set +e
PATH="$(path_of "$tmp/bin")" require_installed "macbook81-cs4208/0.1" "7.2.8-5-omarchy-bore"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "added was treated as installed"
cat > "$tmp/bin/dkms" << 'EOF'
#!/bin/bash
printf '%s\n' "macbook81-cs4208/0.1, 7.2.8-5-omarchy-bore, x86_64: installed"
exit 0
EOF
chmod +x "$tmp/bin/dkms"
PATH="$(path_of "$tmp/bin")" require_installed "macbook81-cs4208/0.1" "7.2.8-5-omarchy-bore" \
    || fail "installed for the running kernel was rejected"
set +e
PATH="$(path_of "$tmp/bin")" require_installed "macbook81-cs4208/0.1" "7.2.5-4-omarchy"
rc=$?
set -e
[[ $rc -eq 1 ]] || fail "another kernel was treated as this kernel"
grep -q 'require_installed "macbook81-cs4208/0.1" "$(uname -r)" || exit 1' \
    install.sh || fail "DONE is not gated on dkms status"

echo "kernel-src tests passed"
