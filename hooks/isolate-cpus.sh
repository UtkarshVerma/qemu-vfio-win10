#!/bin/sh

# Root is required for this hook.
if [ "$(id -u)" -ne 0 ]; then
    exit
fi

set_allowed_cpus() {
    systemctl set-property --runtime -- user.slice AllowedCPUs="$1"
    systemctl set-property --runtime -- system.slice AllowedCPUs="$1"
    systemctl set-property --runtime -- init.scope AllowedCPUs="$1"

    echo "Allowed CPUs set to $1" >&2
}

if [ -z "$CORES" ] || [ -z "$THREADS" ]; then
    exit 1
fi

cpu_range="$(cat /sys/devices/system/cpu/present)"
total=$((${cpu_range#*-} + 1))

case "$1" in
    init) allowed_cpus="0-$((total - CORES * THREADS - 1))" ;;
    cleanup) allowed_cpus="0-$((total - 1))" ;;
    *) exit ;;
esac

set_allowed_cpus "$allowed_cpus"
