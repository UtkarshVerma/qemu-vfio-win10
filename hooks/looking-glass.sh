#!/bin/sh

# Root is required for this hook.
if [ "$(id -u)" -ne 0 ]; then
    exit
fi

# Based on https://looking-glass.io/docs/B6/install/#determining-memory.
compute_shm_size() {
    resolution="$(xdpyinfo | awk '/dimensions/{print $2}')"
    width="${resolution%x*}"
    height="${resolution#*x}"

    color_depth_bits=$(xdpyinfo | grep "depths" | rev | cut -d' ' -f1 | rev)
    color_depth_bytes=$((color_depth_bits / 8))

    frame_bytes=$((width * height * color_depth_bytes * 2))
    frame_mebibytes=$((frame_bytes / 1024 / 1024))
    total_mebibytes=$((frame_mebibytes + 10))

    # Scale to nearest power of 2.
    echo "x=l($total_mebibytes)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l
}

SHM_FILE=/dev/kvmfr0
SPICE_SOCKET=/tmp/spice.sock

case "$1" in
    init)
        # Set up kvmfr (recommended for AMD/Intel iGPUs).
        shmSize="$(compute_shm_size)"
        modprobe kvmfr static_size_mb="$shmSize"
        echo "Shared memory allocated for looking glass" >&2
        sleep 1

        # Ensure that looking glass can access the shared memory.
        if [ "$(stat -c "%U:%G" "$SHM_FILE")" != "$USER:kvm" ]; then
            chown "$USER:kvm" "$SHM_FILE"
            chmod 0660 "$SHM_FILE"
        fi

        echo "\
            -device ivshmem-plain,id=shmem0,memdev=looking-glass \
            -object memory-backend-file,id=looking-glass,mem-path=$SHM_FILE,size=${shmSize}M,share=yes"
        ;;
    post)
        # Ensure that looking glass can access the spice socket.
        if [ "$(stat -c "%U:%G" "$SPICE_SOCKET")" != "$USER:kvm" ]; then
            chown "$USER:kvm" "$SPICE_SOCKET"
        fi

        set -- spice:host="$SPICE_SOCKET" spice:port=0 \
            app:shmFile="$SHM_FILE" win:quickSplash win:noScreensaver input:ignoreWindowsKeys

        export PIPEWIRE_RUNTIME_DIR="/run/user/$(id -u "$USER")"
        sudo -u "$USER" --preserve-env=PIPEWIRE_RUNTIME_DIR looking-glass-client "$@" 1>/tmp/looking-glass.log 2>&1 &
        ;;
    cleanup)
        rmmod kvmfr
        echo "Shared memory deallocated from looking glass" >&2
        ;;
esac
