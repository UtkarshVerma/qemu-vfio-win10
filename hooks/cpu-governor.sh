#!/bin/sh

# Root is required for this hook.
if [ "$(id -u)" -ne 0 ]; then
    exit
fi

CACHE_FILE=/tmp/qemu-cpu-governor
CPU_FILES="/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"

case "$1" in
    init)
        cpu_governors=""
        for file in $CPU_FILES; do
            cpu_governor="$(cat "$file")"
            cpu_governors="$cpu_governors$cpu_governor:"
        done
        echo "$cpu_governors" >"$CACHE_FILE"
        echo "CPU governor set to performance" >&2
        ;;
    cleanup)
        cpu_governors="$(cat "$CACHE_FILE")"
        rm "$CACHE_FILE"

        for file in $CPU_FILES; do
            cpu_governor="${cpu_governors%%:*}"
            echo "$cpu_governor" >"$file"

            cpu_governors="${cpu_governors#*:}"
        done
        echo "CPU governor restored" >&2
        ;;
esac
