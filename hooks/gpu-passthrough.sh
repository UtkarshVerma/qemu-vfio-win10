#!/bin/sh

# Root is required for this hook.
if [ "$(id -u)" -ne 0 ]; then
    exit
fi

set_gpu_profile() {
    supergfxctl --mode "$1" >/dev/null
    echo "GPU profile set to $1" >&2
}

CACHE_FILE=/tmp/qemu-gpu-profile

case "$1" in
    init)
        gpuMode="$(supergfxctl --get)"
        [ "$gpuMode" = "Vfio" ] && exit
        echo "$gpuMode" >"$CACHE_FILE"

        # Pass GPU to the guest.
        set_gpu_profile Vfio

        # QEMU args
        echo "\
            -device ioh3420,bus=pcie.0,addr=1c.0,port=1,chassis=1,id=root.1 \
            -device vfio-pci,host=$GPU,bus=root.1,addr=00.0,multifunction=on,romfile=nvidia.rom \
            -device vfio-pci,host=$GPU_AUDIO,bus=root.1,addr=00.1"

        sleep 0.5
        ;;
    cleanup)
        [ -f "$CACHE_FILE" ] || exit
        gpuMode="$(cat "$CACHE_FILE")"
        rm "$CACHE_FILE"

        # Return GPU to the host.
        set_gpu_profile "$gpuMode"
        ;;
esac
