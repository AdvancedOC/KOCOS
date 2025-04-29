# Complete devfs

Ability to write to partitions and drives.

Ability to actually use the damn thing.

# Radio sockets

"radio" protocol, with "packet" subprotocol.
Connection-less, just send and receive.
Fully supports async I/O.

Still need to be tested.

# Chown syscall

A simple syscall to change a permission at a path.
Requires write permissions for that path.

# mopen mode changes

`r` should return a read-only buffer.
`w` should return a mutable buffer with overwriting.
`a` should return a stream.
`i` should return a mutable buffer with inserting.

# complete syscalls

`syscalls` is very incomplete.

# Make TTY support UTF-8

Currently TTY uses Lua patterns instead of a proper escape parser.
This is fine for some things that can't return unicode, like parsing TTY responses,
but not great for the TTY's OSC command, which absolutely should be able to receive Unicode.

# Custom whole drive partition drivers / devfs drivers

Some components that aren't the vanilla `drive`s may still support
drive-like operations.

To support them, a `KOCOS.quasidrive` module may be added to allow drive-like
operations on non-drive proxies and addresses. It would support fetching
metadrives and whatnot for programs such as `tools/partman.lua` to use.

# Release v0.0.1

At this point the kernel is suitable for an initial alpha release.

# Shrink some things

Refactor the kernel's code a bit to reduce code size post-minification.
The goal is to get the release builds to be smaller, both compressed and decompressed.

# FAT16 driver

Basic FAT16.
No `i` mode or `erase`.

# Stream files in fs

A `mkstream` syscall would make a new `stream` file, which has a callback for writes, reads, seeks and close.
This can be used by programs using virtual standard I/O to be more reactive than waiting for the scheduler to resume them.

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

# More unmanaged filesystem formats
> Because you can never have enough

## Our own partition table
> Name not yet decided. Naming things is an unsolved computer science problem.

A simple partition table, starting at the last sector. (for compatibility with BBR while minimizing wasted space.)
Its structs would be:
```c
// Big endian encoding
// Sector size long.
struct header {
    char header[8]; // header string. 1 char = 1 byte, just like in Lua.
    uint8_t partitionCount;
    uint24_t partitionArray; // 0 for no partition array, stores where extra partitions are if the amount of partitions didn't fit here.
                            // Its capacity shall be assumed to be the largest amount of free space starting there.
                            // IT IS NOT ALLOWED TO POINT INSIDE OF A PARTITION. If it does, the behavior is implementation-defined.
    uint8_t reserved[116]; // first 128 bytes are for data. The padding is reserved and should be filled with 0s.
    struct partition array[]; // primary partition array, stored inside this sector to minimize waste.
};

enum flags {
    READONLY = 1, // this partition should not have its contents modified
    HIDDEN = 2, // this partition may be unimportant to the user, or for internal use only, and thus should be hidden.
    PINNED = 4, // this partition should not be relocated, as something needs it to be there. Typically used for "RESERVED"-type partitions.
};

// 64 bytes long.
struct partition {
    char name[32]; // padded with 0s, 0-terminated.
    uint24_t start; // first sector
    uint24_t len; // length of partition, in sectors.
    uint16_t flags; // see flags. All bits not specified in flags should be set to 0.
    char type[8]; // 8-byte type. Can be treated as a uint64_t or just a string. "BOOT-LDR" is reserved for the bootloader, "@GENERIC" is reserved for
                // generic user partitions, and "RESERVED" is reserved for partitions storing copies of files (sometimes used for boot records).
                // OSs should use them to annotate special functions, NOT FILESYSTEM TYPE.
    uint8_t uuid[16]; // Bytes are in the order seen in the stringified version.
};
```

## A new, conventional filesystem
> Name not yet decided. Naming things remains an unsolved computer science problem.

A conventional filesystem (no `i` mode or `erase` syscall support like OKFFS), designed to be fast and simple.
Its format should be simple enough to fit on a BIOS.
Exact details not known yet.

Ideas:
- Instead of free list, the blocks between the superblock and the free space have a byte at the start, with a bit flag that stores if they are in use. This
means freeing can be, well, almost free, as there is basically no need to seek.
- Blocks have headers with the special starting flags byte but also the next block in the list.
- `spaceUsed` is computed and probably cached, instead of stored as an active block count. This is to eliminate the need to seek often.
- Free space index not being exactly the sector, but instead the index in a theoretical list of blocks that reduces seeks by going platter-by-platter first.
Block id would remain as just the sector. Essentially, if there are 4 sectors per platter, and 2 platters, the theoretical list would be sectors 1, 5, 2, 6,
3, 7, 4, 8.
- Make heavy use of caching in the driver. At least a read cache like the one in OKFFS.
