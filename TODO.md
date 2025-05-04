# More unmanaged filesystem formats
> Because you can never have enough

## LightFS (Lightweight File System)

A conventional filesystem (no `i` mode or `erase` syscall support like OKFFS), designed to be fast and simple.
Its format should be simple enough to fit on a BIOS.

```c
// First sector. Rest of sector is 0'd.
// Sector IDs start from 0, not 1 like in OC drives.
// Its all little endian btw
// Block IDs also start from 0, though block 0 is the superblock.
struct superblock {
    char header[8] = "LightFS\0";
    uint24_t nextFreeBlock;
    uint24_t rootSector;
    uint24_t firstFreeSector; // first sector in free list.
    uint8_t mappingAlgorithm; // mapping algorithm used on the device
};

enum mappingAlgorithm {
    INITIAL = 1,
};

struct block {
    uint24_t nextBlockSector; // sector of next block in block list. 0 
    uint8_t data[]; // rest of sector
};

struct freeBlock {
    uint24_t nextBlockSector; // once we free this, the next block to put in the free list, unless it is 0.
    uint24_t nextFreeSector; // sector of next block in the free list
};

enum ftype {
    FILE = 0,
    DIRECTORY = 1,
};

// directory blocklists are just like file blocklists, but the file contents are a sequence of dirEntries.
struct dirEntry {
    char name[32]; // NULL-terminated. Empty for deleted files.
    uint64_t mtimeMS;
    uint16_t permissions;
    uint8_t ftype;
    uint24_t firstBlockListSector;
    uint32_t fileSize;
    uint8_t reserved[14];
};
```

### Free List

The free list stores the first blocks in the block lists that are freed. When a block is recycled from the free list, the free list is set to
the next block in the original block list that was freed (the `nextBlockSector` field), unless it is 0, in which case it is set to the next freed block
list (the `nextFreeSector` field).

### Block ID to Sector

LightFS, to minimize time spent seeking, it uses **platter-aware block ID to sector mappings**, which means the next block ID is more likely than not in the
same position on the next platter, which means there is no need to seek. (which can be very slow)

The algorithm for mapping Block IDs to sectors, given a `physicalPlatterCount` and `totalSectors`, is:
```lua
-- For mappingAlgorithm = INITIAL
local function initial(blockID, physicalPlatterCount, totalSectors)
    local sectorsPerPlatter = math.floor(totalSectors / physicalPlatterCount)
    local logicalPlatterCount = math.floor(totalSectors / sectorsPerPlatter)

    local blocksPerPlatter = math.max(1, math.floor(totalSectors / logicalPlatterCount))

    local x = math.floor(blockID / blocksPerPlatter)
    local y = blockID % blocksPerPlatter

    return x + y * blocksPerPlatter
end
```
`physicalPlatterCount` is the platter count of the **drive**, whilst `totalSectors` is the amount of sectors in the **partition.**

Due to how `logicalPlatterCount` is computed, it is **highly recommended** to make the partition **platter-aligned.**

This algorithm does mean that LightFS partitions are **non-resizable without re-formatting**, because the variables in this equation would change.


# Release v0.0.1

At this point the kernel is suitable for an initial alpha release.

# Symlinks

We kinda should have symlinks

# Shrink some things

Refactor the kernel's code a bit to reduce code size post-minification.
The goal is to get the release builds to be smaller, both compressed and decompressed.


# Support pasting in TTY keyboard mode

Minor thing but like kinda cool

# Fix okffs_ro

It appears the portable OKFFS implementation is broken.
Lets fix that with a controlled shock.

# OKFFS test suite improvements

Testing `w` and `a` modes.
Testing `erase` once implemented.

# OKFFS mode changes

Add a `erase` syscall to erase bytes starting at the file position.
ManagedFS won't support `erase`.

# OKFFS optimizations

Smarter block allocator that is aware of platters.
Grouping writes to work smarter.
Reducing seek times.

# KVM - KOCOS Virtual Machines

## KVM Virtual Networks

Virtual Modems can be added which use *Virtual Networks.*
They can be bound to one virtual network.
A virtual network is identified by a string key.
They can communicate across virtual machines.

Virtual Modems can also be given virtual X/Y/Z coordinates to compute signal distances.
They default to 0/0/0.

They send `modem_message` signals.

## KVM command for basic VMs

```sh
# Example usage of a graphical OS
# --bios sets the bios
# --filesystem mounts a new folder as a filesystem. --filesystem-readonly would be used for read only filesystems.
# --vgpu mounts a new virtual GPU.
# --tuiscreen mounts a new TUI screen. This also clears the terminal.
# --allowMount=always will always allow mounts without user confirmation.
# --epass will pass events through.
~ > kvm --bios myBIOS.lua --filesystem openos_dir --vgpu --tuiscreen --allowMount=always --epass key_down --epass key_up
# OpenOS boots and takes over.
```

```sh
# Example usage of a theoretical patched OpenOS which supports interfacing with the KOCOS component.
~ > kvm --bios myBIOS.lua --filesystem openos_patched --kocos
# OpenOS bootup...
# > echo hi
hi
# > # continue to do stuff
# > exit
~ > # back to host
```
## libkvm and kvm

`/lib/libkvm.so` will provide a convenient wrapper for the KVM system.
`tools/kvm.lua` will be a simple script that uses `/lib/libkvm.so`.

# Ridiculous memory shrinking

A lot of RAM optimizations to be made, such as:
- _SHARED and shared storage between processes (liblua can use that to recycle stuff)
- Shared `syscall`. Instead, `KOCOS.process.current()` is designed to find the current `pid`.
- Threads stored in a linked list, with new ones inserted at the start.
- Lazily created interrupt queue. Created when listeners get made.

## How to find the current process

To avoid callbacks causing unfortunate mistakes, we need `KOCOS.process.current()` to get the current pid of the running process.
The only reliable source for this information is the source locations returned by `debug.getinfo`.
The way we do it is simple, every process' `load` annotates the pid in the source location. Say it is set to `abc`, then it would be changed to `pid0-abc`.
Then when we query, we check if `debug.getinfo(level, "S").source` matches `^pid(%d+)%-`, in which case we grab that match and parse it to get the pid.
To prevent awful stack traces, we patch `debug.traceback()` to replace `pid%d+%-%:([^%s]+)` with the first capture (aka remove the dumb pids.
This would be a mostly transparent change. This opens the door to more effective caching of libraries, but also letting `KOCOS.process.current()` ignore
certain pids while tracing for drivers to be able to identify *their* callers.

This feature would also automatically make KOCOS 100x cooler.

# Audio System
> KOCOS.audio

Audio System which lets you register devices to play notes.

Notes that should be supported:
- harp (default noteblock)
- basedrum
- bass
- bell
- chime
- flute
- guitar
- hat
- pling
- snare
- xylophone

# FAT16 driver
> This may never be added

Basic FAT16.
No `i` mode or `erase`.
