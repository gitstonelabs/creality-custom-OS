#!/bin/bash
WRAP="$HOME/buildroot-creality-hi-out/host/bin/udevadm"
echo "wrap: $WRAP"
echo "type: $(file "$WRAP")"
echo "----- INVOKE hwdb --update -----"
"$WRAP" hwdb --update --root /tmp
echo "exit=$?"
