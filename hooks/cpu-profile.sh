#!/bin/sh

set_cpu_profile() {
    asusctl profile --profile-set "$1"
    echo "CPU profile set to $1" >&2
}

CACHE_FILE=/tmp/qemu-cpu-profile

case "$1" in
    init)
        cpuMode="$(asusctl profile --profile-get | cut -d' ' -f4)"
        [ "$cpuMode" = "Performance" ] && exit
        echo "$cpuMode" >"$CACHE_FILE"

        # Switch to performance mode.
        set_cpu_profile Performance
        ;;
    cleanup)
        [ -f "$CACHE_FILE" ] || exit
        cpuMode="$(cat "$CACHE_FILE")"
        rm "$CACHE_FILE"

        # Switch back to the initial mode.
        set_cpu_profile "$cpuMode"
        ;;
esac
