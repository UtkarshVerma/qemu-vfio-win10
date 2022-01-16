#!/bin/sh

# Ensure that the script is always run as root
if [ $(id -u) -ne 0 ]; then
	echo "$0 needs to be run as root!"
	exec sudo $0 $@
fi

USER=subaru
RAM=4
CORES=2
THREADS=2
GPU=01:00.0
GPU_AUDIO=01:00.1
SHARED_FOLDER=/media/stuff

# Parse CLI flags
USE_SPICE=0
USE_HUGEPAGES=0
USE_DMABUF=1;
WEBCAM=0;
while [ $# -gt 0 ]; do
  case $1 in
	-w|--webcam) WEBCAM=1; shift ;;
	-s|--spice) USE_SPICE=1; shift ;;
	-h|--hugepages) USE_HUGEPAGES=1; shift ;;
	-f|--fullscreen) lgArgs="-F"; shift ;;
	-nd|--nodmabuf) USE_DMABUF=0; shift ;;
  esac
done

lgArgs="$lgArgs -S"

# Bind GPU to guest
gfxMode="$(supergfxctl -g | awk '{print $NF}')"
supergfxctl -m vfio

# Allocate memory hugepages
if [ $USE_HUGEPAGES -ne 0 ]; then
	hugepages=/dev/hugepages
	hugepageSize=$(grep Hugepagesize /proc/meminfo | awk '{print $2}')
	[ -d $hugepages ] || mkdir $hugepages
	mountpoint -q -- $hugepages || mount -t hugetlbfs hugetlbfs $hugepages
	echo 3 > /proc/sys/vm/drop_caches && echo 1 > /proc/sys/vm/compact_memory && echo $((512*RAM)) > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages
	args="$args -mem-path $hugepages"
fi

# Input devices
if [ $USE_SPICE -eq 1 ]; then
	# Use SPICE
	spicePort=5900
	lgArgs="$lgArgs -p $spicePort"
	args="$args \
		-device virtio-serial-pci \
		-spice port=$spicePort,disable-ticketing=on \
		-chardev spicevmc,name=vdagent,id=vdagent \
		-device virtserialport,chardev=vdagent,name=com.redhat.spice.0"
else
	# Use evdev with persistent-evdev.py
	./persistent-evdev.py persistent-evdev.json &
	pEvdevPID=$!
	sleep 1

	args="$args \
		-object input-linux,id=mouse,evdev=/dev/input/by-id/uinput-persist-mouse \
		-object input-linux,id=touchpad,evdev=/dev/input/by-id/uinput-persist-touchpad \
		-object input-linux,id=kbd0,evdev=/dev/input/by-id/uinput-persist-keyboard0,grab_all=on,repeat=on \
		-object input-linux,id=kbb1,evdev=/dev/input/by-id/uinput-persist-keyboard1,grab_all=on,repeat=on"
	lgArgs="$lgArgs -s"
	
	echo
fi

# Pass through the webcam
if [ $WEBCAM -eq 1 ]; then
	args="$args \
		-device qemu-xhci,id=xhci \
		-device usb-host,hostbus=3,hostaddr=2"
fi

# Create shared memory for looking-glass, if it doesn't exist
shmSize=32
if [ $USE_DMABUF -eq 1 ]; then
	shmFile=/dev/kvmfr0
	modprobe kvmfr static_size_mb=$shmSize
	sleep 1
else 
	shmFile=/dev/shm/looking-glass
	touch $shmFile
fi

lgArgs="$lgArgs -f $shmFile"
if [ "$(stat -c '%U:%G' $shmFile)" != "$USER:kvm" ]; then
	chown $USER:kvm $shmFile
	chmod 0660 $shmFile
fi
args="$args \
	-device ivshmem-plain,id=shmem0,memdev=looking-glass,bus=pcie.0 \
	-object memory-backend-file,id=looking-glass,mem-path=$shmFile,size=${shmSize}M,share=yes"

# Switch to performance mode
laptopMode="$(asusctl profile -p | awk '{print $NF}')"
asusctl profile -P Performance

# Setup Jack with PipeWire backend
export PIPEWIRE_RUNTIME_DIR="/run/user/1000"
export PIPEWIRE_LATENCY="512/48000"
inputArgs="in.client-name=Windows,in.connect-ports=Family.*capture_F[LR]"
outputArgs="out.client-name=Windows,out.connect-ports=Family.*playback_F[LR]" 
args="$args \
	-audiodev jack,id=ad0,$inputArgs,$outputArgs \
	-device ich9-intel-hda,bus=pcie.0,addr=0x1b,msi=on \
	-device hda-duplex,audiodev=ad0"

# QEMU
nice -n -5 \
jemalloc.sh \
qemu-system-x86_64 \
	-enable-kvm \
	-name "Windows 10",debug-threads=on \
	-machine type=q35,usb=off,vmport=off,kernel_irqchip=on,accel=kvm \
	-cpu host,topoext,tsc_deadline,tsc_adjust,hv_vendor_id=random,hv_relaxed,hv_vpindex,hv_runtime,hv_synic,hv_stimer,hv_reset,hv_frequencies,hv_tlbflush,hv_reenlightenment,hv_time,-aes,hv_vapic,hv_spinlocks=0x1fff,hv_ipi,-kvm,l3-cache \
	-smp $((CORES*THREADS)),sockets=1,cores=$CORES,threads=$THREADS \
	-m ${RAM}G \
	-overcommit mem-lock=off,cpu-pm=on \
	-rtc clock=host,base=localtime,driftfix=slew \
	-global kvm-pit.lost_tick_policy=delay \
	-no-hpet \
	-msg timestamp=on \
	-acpitable file=SSDT1.dat \
	-drive file=OVMF_CODE.fd,readonly=on,format=raw,if=pflash \
	-drive file=OVMF_VARS.fd,format=raw,if=pflash \
	-object iothread,id=diskio \
	-device virtio-scsi-pci,iothread=diskio,id=scsi,num_queues=$((CORES*THREADS)) \
	-device scsi-hd,drive=hdd \
	-drive file=hdd.qcow2,id=hdd,if=none \
	-netdev user,id=nic,smb=$SHARED_FOLDER \
	-device virtio-net,netdev=nic \
	-object rng-random,id=rng,filename=/dev/urandom \
	-device virtio-rng-pci,rng=rng \
	-device vfio-pci,host=$GPU,x-vga=on,multifunction=on \
	-device vfio-pci,host=$GPU_AUDIO \
	-device virtio-mouse-pci \
	-device virtio-keyboard-pci \
	-boot menu=off,strict=on \
	-serial none \
	-parallel none \
	-vga none \
	-nographic \
	-nodefaults \
	-no-user-config \
	-monitor unix:/tmp/qemuwin.sock,server,nowait \
	$args &

echo
sleep 1

qemuPID=$!
total=$(nproc)
offset=$((total-CORES*THREADS))
extraCores=$((offset-2))-$((offset-1))
./qemu-affinity $qemuPID -v \
	-p $extraCores \
	-q $extraCores \
	-i *:$extraCores \
	-w *:$extraCores \
	-k $(seq -s ' ' $((offset)) $((total-1)))

echo
sleep 5

# Run looking-glass-client as normal user
sudo -u $USER looking-glass-client $lgArgs 1>/tmp/looking-glass.log 2>&1 &

# Wait for QEMU to exit
wait $qemuPID

# Restore initial laptop mode
asusctl profile -P $laptopMode
echo

# Kill looking-glass-client, and persistent-evdev after VM shuts down
if [ $USE_SPICE -ne 1 ]; then
	kill $(pidof looking-glass-client)
	kill $pEvdevPID
fi

# Clean up hugepages
if [ $USE_HUGEPAGES -ne 0 ]; then
	sysctl vm.nr_hugepages=0
	umount $hugepages
fi

# Return GPU to host
supergfxctl -m $gfxMode

# Remove kvmfr kernel module
[ $USE_DMABUF -eq 1 ] && rmmod kvmfr
