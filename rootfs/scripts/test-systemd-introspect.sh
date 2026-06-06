#!/bin/bash
# test-systemd-introspect.sh — diagnose why host-systemd's --bus-introspect crashes
SYSD="$HOME/buildroot-creality-hi-out/build/host-systemd-250.4/build/systemd"

if [ ! -x "$SYSD" ]; then
    echo "ERROR: $SYSD not found or not executable"
    exit 1
fi

echo "Binary: $SYSD"
echo "Glibc: $(ldd --version | head -1)"
echo

echo "--- 1) default invocation ---"
"$SYSD" --bus-introspect list 2>&1 | head -5
echo "exit=$?"

echo
echo "--- 2) with LD_FORTIFY_DISABLE ---"
LD_FORTIFY_DISABLE=1 "$SYSD" --bus-introspect list 2>&1 | head -5
echo "exit=$?"

echo
echo "--- 3) with GLIBC_TUNABLES=glibc.malloc.check=0 ---"
GLIBC_TUNABLES=glibc.malloc.check=0 "$SYSD" --bus-introspect list 2>&1 | head -5
echo "exit=$?"

echo
echo "--- 4) with MALLOC_CHECK_=0 ---"
MALLOC_CHECK_=0 "$SYSD" --bus-introspect list 2>&1 | head -5
echo "exit=$?"

echo
echo "--- 5) with all checks off ---"
GLIBC_TUNABLES=glibc.cpu.hwcaps= MALLOC_CHECK_=0 LD_FORTIFY_DISABLE=1 "$SYSD" --bus-introspect list 2>&1 | head -5
echo "exit=$?"
