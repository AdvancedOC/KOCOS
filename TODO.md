# Keyboard System
> KOCOS.keyboard

Global keyboard interface that is very extra good.

Also TTY keyboard input via the aux port.

# Radio sockets

"radio" protocol, with "packet" subprotocol.
Connection-less, just send and receive.
Fully supports async I/O.

# more liblua modules

`terminal` to provide an API around escape codes.
`dl` for dynamic linking (and, subsequently, support for requiring kelp libraries)

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

# Chown syscall

A simple syscall to change a permission at a path.
Requires write permissions for that path.

# OKFFS mode changes

Make `w` mode overwrite instead. OKFFS `w` mode is currently broken and needs fixing.
Add a `erase` syscall to erase bytes starting at the file position.

ManagedFS won't support `a` or `erase`.

# OKFFS optimizations

Smarter block allocator that is aware of platters.
Grouping writes to work smarter.
Reducing seek times.

# KVM - KOCOS Virtual Machines

Simulating an OpenComputers computer with either virtual hardware or passed through hardware.
It has its own "vm" resource, with its own event system.

## Basic overview

A `kvmopen` syscall is used to open a new blank virtual machine.
`kvmresume` can be used to run it until it yields. Pulling signals always yields.
It will return if the machine *is still running*. If false, a 2nd return is made.
A string if it crashed due to an error, a boolean if it shutdown, indicating whether it wishes to restart.
`kvmadd` can be used to add a virtual component by proxy, more on that later.
Can be told to raise a `component_added` event.
`kvmaddGPU` can be used to add a virtual GPU that can be bound to a screen and forwards all the
calls to the screen's internal vgpu calls.
`kvmpass` can be used to pass through a real component as a virtual component. This requires
permission to use said real component, so passing through drives, eeproms, gpus or screens will require
ring 1 or ring 0.
`kvmremove` can be used to remove a virtual component from a VM. Will raise a `component_removed` event.
`kvmlisten` can be used to pass through events from the host to the VM.
`kvmforget` can be used to stop passing through events from the host to the VM.
`kvmsettmp` can be used to set the result of `computer.tmpAddress()`.
`kvmusers` can be used to set the reported users of the computer. `addUser` will add to the list of users,
but will not be remembered.
`kvmenv` can be used to get the globals of the VM. This can be used to patch anything if needed.

## Virtual Components

```lua
-- Basic interface
local component = {
    type = "screen",
    slot = -1,
    -- For getDeviceInfo
    info = {

    },
    methods = {
        -- actual normal screen methods
        -- errors are thrown, not returned.
    },
    -- Optional
    docs = {
        method = "docstring",
    },
    -- Destructor
    close = function()

    end,
    -- internal storage for component-to-component data.
    internal = {
        -- KVM-provided VGPUs will use this.
        -- This allows you to have a TUI screen, a remote screen,
        -- or a real screen.
        vgpu = {
            set = function(x, y, s)
                -- do stuff
            end,
            -- etc.
        },
    },
}
```

## Events

```lua
local vm = kvmopen()

-- when a signal needs to be queued, we use the event syscalls
push(vm, "key_down", keyboardAddr, 0, 0, "player")
```

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

### The KOCOS component

```lua
-- 0 for stdout, 1 for stdin, 2 for stderr.
-- suppose OpenOS-style primaries
local kocos = component.kocos

kocos.write(0, "Hello!\n")
local line = kocos.read(1, math.huge) -- simplification

local os = kocos.getHost() -- gets the host _OSVERSION
local kvm = kocos.getVirtualizer() -- gets the version of KVM used.

print(os, kvm)
```

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
"kocos_mount" <path> # Adds filesystem or drive component. Response data is path
"kocos_remove" <component address> # Removes component. Response data is a boolean
"kocos_passed" <component address> # Passed component.
```
