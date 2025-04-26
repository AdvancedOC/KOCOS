# More Advanced TTY

The ability to move the cursor is pretty damn important
Also tab for autocomplete.

## Autocomplete

Reading the TTY with `-1` as the length enables autocomplete.
This means when the user presses tab, instead of doing nothing, it will send the line with the tab character where you pressed tab.
The shell will then go in autocomplete mode, where the next write will then be written, with the tab character specifying
where the cursor should be placed.

# Radio sockets

"radio" protocol, with "packet" subprotocol.
Connection-less, just send and receive.
Fully supports async I/O.

# more liblua modules

`terminal` to provide an API around escape codes.
`keyboard` to provide keyboard codes.
`socket` to provide convenient wrappers around sockets.

We gotta complete `syscalls` too

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

# Complete devfs

`/dev/eeprom` and `/dev/eeprom-data`

Ability to write to partitions and drives.

Ability to actually use the damn thing.

# Chown syscall

A simple syscall to change a permission at a path.
Requires write permissions for that path.

# Fix okffs_ro

It appears the portable OKFFS implementation is broken.
Lets fix that with a controlled shock.

# mopen mode changes

`r` should return a read-only buffer.
`w` should return a mutable buffer with overwriting.
`a` should return a stream.
`i` should return a mutable buffer with inserting.

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

## KVM command's OS interop API

### Signals

```lua
-- In OpenOS

event.push("kocos_mount", "/etc/stuff")
-- suppose the response was instantly pushed. In a real OS, wait for this signal.
local _, data, err = event.pop("kocos_response")
-- The data is just the uuid of the component added. It is nil if rejected.
local uuid = assert(data, err)
-- We asked to mount a folder, so we get a filesystem component.
-- We can mount it in the VM's virtual filesystem.
-- Now those 2 are bound together.
filesystem.mount(uuid, "/etc/stuff")
```

```sh
# Responses are
"kocos_response" <data> <err>
# Things VM can do
"kocos_mount" <path> # Adds filesystem or drive component. Response data is address. Path can be to folder for filesystem and to file for drive.
"kocos_remove" <component address> # Removes component. Response data is a boolean
"kocos_vgpu" # Adds a VGPU. Reponse data is address.
```

## libkvm and kvm

`/lib/libkvm.so` will provide a convenient wrapper for the KVM system.
`tools/kvm.lua` will be a simple script that uses `/lib/libkvm.so`.

# Ridiculous memory shrinking

A lot of RAM optimizations to be made, such as:
- _SHARED and shared storage between processes (liblua can use that to recycle stuff)
- Shared `syscall`. Instead, a global `Context` is made to store the current thread.
- Threads stored in a linked list, with new ones inserted at the start.
- Lazily created interrupt queue. Created when listeners get made.

## New syscalls to circumvent new challenges

### klisten and kforget

Add a listener to kernel events
```lua
local l = klisten(function()
    
end)

-- continue running

kforget(l) -- also ran automatically by the kernel
```

### Note on drivers

The context is not switched when a driver runs. Thus, any syscalls they do are in the context of the caller.
The caller can be very unexpected.
If contexts were temporarily switched, it'd be a security hole.
