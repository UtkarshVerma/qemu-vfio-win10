#!/bin/sh

# Root is required for this hook.
if [ "$(id -u)" -ne 0 ]; then
    exit
fi

allocate_hugepages() {
    echo "$1" >"$HUGEPAGE_FILE"
    allocated="$(cat /proc/sys/vm/nr_hugepages)"
    if [ "$allocated" -ne "$1" ]; then
        return 1
    fi

    if [ "$allocated" -eq 0 ]; then
        echo "Released all allocated pages" >&2
        return
    fi

    echo "Allocated $allocated pages" >&2

    hugepage_mount=/dev/hugetlbfs
    [ -d "$hugepage_mount" ] || mkdir "$hugepage_mount"
    mountpoint --quiet -- "$hugepage_mount" || mount --types hugetlbfs hugetlbfs "$hugepage_mount"

    # QEMU args
    echo "\
        -object memory-backend-file,id=pc.ram,size=${RAM}G,mem-path=$hugepage_mount,prealloc=on,share=on
        -machine memory-backend=pc.ram"
}

if [ -z "$RAM" ]; then
    exit 1
fi

HUGEPAGE_SIZE="$(grep Hugepagesize /proc/meminfo | awk '{print $2}')"
HUGEPAGE_FILE="/sys/kernel/mm/hugepages/hugepages-${HUGEPAGE_SIZE}kB/nr_hugepages"

case "$1" in
    init)
        memory="$((RAM * 1024 * 1024))"
        hugepage_count="$((memory / HUGEPAGE_SIZE))"

        if allocate_hugepages "$hugepage_count"; then
            exit
        fi

        # Drop caches to free up memory for hugepages if not successful.
        echo 3 >/proc/sys/vm/drop_caches

        # If not successful, retry multiple times.
        TRIES=0
        MAX_TRIES=1000
        while [ $TRIES -lt $MAX_TRIES ]; do
            # Defragment RAM and try to allocate pages again.
            echo 1 >/proc/sys/vm/compact_memory

            if allocate_hugepages "$hugepage_count"; then
                exit
            fi

            TRIES=$((TRIES + 1))
        done

        # If still unable to allocate requested pages, revert hugepages and quit.
        echo "Not able to allocate all hugepages. Reverting..." >&2
        echo 0 >/proc/sys/vm/nr_hugepages

        exit 1
        ;;
    cleanup)
        allocate_hugepages 0
        ;;
    *) exit ;;
esac
