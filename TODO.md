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

# Release v0.0.1

At this point the kernel is suitable for an initial alpha release.

# Shrink some things

Refactor the kernel's code a bit to reduce code size post-minification.
The goal is to get the release builds to be smaller, both compressed and decompressed.

# FAT16 driver

Basic FAT16.
No `i` mode or `erase`.

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
