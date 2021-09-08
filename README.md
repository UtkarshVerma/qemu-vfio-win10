# qemu-vfio-win10
This repo aims to serve as an example for getting VFIO passthrough working on a Windows 10 guest on Linux. Plain QEMU has been used to keep things minimal, and distro-specific utilities have been avoided to keep things general.

## Features
The script has the following features:
- Hugepages
- HyperV enlightenments
- Dynamic VFIO passthrough for NVIDIA GPU, i.e. GPU is usable by host after guest exits.
- Respects NVIDIA Runtime D3 power management
- `evdev` passthrough using `persistent-evdev.py`
- Looking Glass
  - SPICE input and clipboard sharing
  - DMA buffer support
  - Auto shared memory creation
- virtio devices
- `pulseaudio` audio device passthrough
- CPU pinning with `qemu-affinity`
- CPU governor configuration
- Runs QEMU with jemalloc() memory allocator

## Usage
This script assumes you already have a working Windows 10 guest set up for Looking Glass and GPU passthrough. If you are new to VFIO passthrough, then these links should get you started:
- [PCI passthrough via OVMF - Arch Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
- [GPU passthrough with libvirt qemu kvm](https://wiki.gentoo.org/wiki/GPU_passthrough_with_libvirt_qemu_kvm)
- [Looking Glass Docs](https://looking-glass.io/docs/stable/install/)

Once you have a working Windows 10 guest, move the disk image file to this folder and rename it to `hdd.qcow2`. After that copy the OVMF file descriptors `OVMF_CODE.fd` and `OVMF_VARS.fd` next to the script as well so that you get the following tree:
```
.
├── LICENSE
├── OVMF_CODE.fd
├── OVMF_VARS.fd
├── README.md
├── SSDT1.dat
├── hdd.qcow2
├── launch.sh
├── persistent-evdev.json
├── persistent-evdev.py
├── qemu-affinity
└── vfio

0 directories, 11 files
```

You'll also need to configure a few variables in the script according to your machine.

```sh
USER=subaru                     # Your username
RAM=5                           # RAM, in GB
CORES=3                         # No. of cores
THREADS=2                       # No. of threads per core
GPU=01:00.0                     # PCI address of your NVIDIA GPU
GPU_AUDIO=01:00.1               # PCI address of your NVIDIA GPU's audio function
SHARED_FOLDER=/media/stuff      # Folder to be shared to guest
```

Once that is out of the way, make sure you have `jemalloc` installed on your machine, and `persistent-evdev.py` configured through `persistent-evdev.json` if you plan on using `evdev` passthrough. Also make sure you have installed the `qemu-affinity` python package.

```sh
pip install qemu-affinity
```

Once that's done, run the launch script as root, and you're good to go.

```sh
sudo ./launch.sh
```

Running this command starts the guest and opens Looking Glass, with the QEMU monitor socket opened on `/tmp/qemuwin.sock`.

The script supports some command line flags:

Flags|Usage
-|-
`-s` / `--spice`|Use SPICE for input instead of evdev. Defaults to `evdev`.
`-h` / `--hugepages`|Use hugepages. Disabled by default.
`-f` / `--fullscreen`|Open the guest in fullscreen. Disabled by default.
`-nd` / `--nodmabuf`|Disable DMABUF for Looking Glass, which is enabled by default.

### What to expect from the guest
The guest performs really well for a VM. I don't experience any freezes. For normal usage and light gaming (Brawlhalla), I couldn't notice any issues with this setup on my laptop (ASUS TUF FX505DT).

## Credits 
This workflow would not have been possible without the following tools.
- [QEMU](https://www.qemu.org/)
- [Looking Glass](https://looking-glass.io/)
- [jemalloc](http://jemalloc.net/)
- [persistent-evdev.py](https://github.com/aiberia/persistent-evdev)
- [qemu-affinity](https://github.com/zegelin/qemu-affinity)
