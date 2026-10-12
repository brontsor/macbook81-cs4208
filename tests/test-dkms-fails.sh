#!/bin/bash
# A failed dkms install must fail this script. Do not run dkms.sh until it
# honors a temp tree: the default paths are the live package on this machine.
set -eu
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q '^set -eu$' dkms.sh || fail "dkms.sh does not fail the caller when a command fails"
grep -q 'MB81_DKMS_SRC' dkms.sh || fail "dkms.sh has no test path override; refusing to run it"
grep -q 'MB81_DKMS_VAR' dkms.sh || fail "dkms.sh has no test state override; refusing to run it"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/src" "$tmp/var"
cat > "$tmp/bin/dkms" << EOF
#!/bin/bash
echo "\$*" >> "$tmp/dkms.log"
if [[ \$1 == install ]]; then
    exit 1
fi
exit 0
EOF
cat > "$tmp/bin/depmod" << EOF
#!/bin/bash
echo ran >> "$tmp/depmod.log"
exit 0
EOF
chmod +x "$tmp/bin/dkms" "$tmp/bin/depmod"

set +e
PATH="$tmp/bin:$PATH" \
    MB81_SKIP_INITRAMFS=1 \
    MB81_DKMS_SRC="$tmp/src/link" \
    MB81_DKMS_VAR="$tmp/var/tree" \
    bash dkms.sh >"$tmp/out" 2>"$tmp/err"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "dkms.sh exited 0 after dkms install failed"
[[ ! -f $tmp/depmod.log ]] || fail "depmod ran after dkms install failed"
echo "dkms failure test passed"
