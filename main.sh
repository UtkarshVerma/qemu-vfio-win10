#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
    echo "error: root access is required"
    exit 1
fi

sigint_handler() {
    kill "$QEMU_PID"
}

execute_hooks() {
    for hook in ./hooks/*.sh; do
        $hook "$1"
    done
}

export \
    USER=subaru \
    RAM=4 \
    CORES=2 \
    THREADS=2 \
    GPU=01:00.0 \
    GPU_AUDIO=01:00.1 \
    SPICE_SOCKET=/tmp/spice.sock

while [ $# -gt 0 ]; do
    case $1 in
        --cdrom)
            export CDROM="$2"
            shift
            ;;
        --share)
            export SHARED_FOLDER="$2"
            shift
            ;;
        --usb)
            export USB_DEVICES="$USB_DEVICES $2"
            shift
            ;;
    esac

    shift
done

args="$(execute_hooks init)"

# CDROM
if [ -n "$CDROM" ]; then
    args="$args \
        -drive file=$CDROM,format=raw,if=none,media=cdrom,id=os-cd,readonly=on \
        -device ahci,id=achi0 \
        -device ide-cd,bus=achi0.0,drive=os-cd,id=cd,bootindex=1"
fi

# Networking
args="$args \
    -netdev user,id=nic${SHARED_FOLDER:+,smb=$SHARED_FOLDER} \
    -device virtio-net,netdev=nic"

# USB device passthrough
if [ -n "$USB_DEVICES" ]; then
    args="$args \
        -device qemu-xhci,id=xhci"

    for device in $USB_DEVICES; do
        bus="${device%,*}"
        addr="${device#*,}"

        args="$args \
            -device usb-host,hostbus=$bus,hostaddr=$addr"
    done
fi

# Spice
args="$args \
    -device virtio-serial-pci \
    -chardev spicevmc,name=vdagent,id=vdagent \
    -device virtserialport,chardev=vdagent,name=com.redhat.spice.0 \
    -spice unix=on,addr=$SPICE_SOCKET,disable-ticketing=on,seamless-migration=off"

# Audio
args="$args \
    -audiodev spice,id=sound \
    -device ich9-intel-hda \
    -device hda-duplex,audiodev=sound"

# Hard drive
args="$args \
    -object iothread,id=diskio \
    -device virtio-scsi-pci,iothread=diskio,id=scsi,num_queues=$((CORES * THREADS)) \
    -device scsi-hd,drive=ssd,bootindex=2 \
    -drive file=hdd.qcow2,id=ssd,if=none"

# Display
args="$args \
    -vga std"

# UEFI
args="$args \
	-drive file=OVMF_CODE.fd,readonly=on,format=raw,if=pflash \
	-drive file=OVMF_VARS.fd,format=raw,if=pflash"

# Windows-specific args: Spoof a battery to avoid NVIDIA's Code 43.
args="$args \
    -acpitable file=SSDT1.dat"

qemu_cmd="qemu-system-x86_64 \
	-enable-kvm \
	-name Windows,debug-threads=on \
	-machine type=q35,hpet=off,usb=off,vmport=off,kernel_irqchip=on,accel=kvm \
	-cpu host,topoext,tsc_deadline,tsc_adjust,hv_vendor_id=random,hv_relaxed,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_reset,hv_frequencies,hv_tlbflush,hv_reenlightenment,hv_time,-aes,hv_vapic,hv_spinlocks=0x1fff,hv_ipi,-kvm,l3-cache \
	-smp $((CORES * THREADS)),sockets=1,cores=$CORES,threads=$THREADS \
	-m ${RAM}G \
	-overcommit mem-lock=off,cpu-pm=on \
    -rtc base=utc,clock=host,driftfix=slew \
	-global kvm-pit.lost_tick_policy=delay \
	-msg timestamp=on \
	-object rng-random,id=rng,filename=/dev/urandom \
	-device virtio-rng-pci,rng=rng \
	-device virtio-mouse-pci \
	-device virtio-keyboard-pci \
	-boot menu=off,strict=on \
    -serial none \
    -parallel none \
    -nodefaults \
	-no-user-config \
	-monitor unix:/tmp/qemu-windows.sock,server,nowait \
	$args"

$qemu_cmd &
export QEMU_PID=$!
sleep 1

execute_hooks post

trap sigint_handler INT
wait "$QEMU_PID"
sleep 1

execute_hooks cleanup
