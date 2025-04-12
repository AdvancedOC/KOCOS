# libkernel

Library that defines wrappers for all the syscalls.

# Domain Sockets

A new "domain" protocol with the "channel" subprotocol.
These communicate via IPC, where the address is a key into a big table.

# User/system yields

User resumes should be overpowered by system yields, and system resumes should be the most powerful.
It lets drivers yield in their synchronous interface without affecting green threads.
It lets `exit` syscall work.

# exit syscall

Basic syscall to set an exit code and terminate all threads. Does not kill the process though.

# prevent running after death

When a thread kills its process, it continues to run until it yields. It should do a system yield.

# tkill, tjoin, tsuspend and tresume syscalls

A way to kill a thread, wait for it to finish, pause its execution or resume its execution.

# trace option when spawning processes

If set to `true`, parent will receive interrupts for each syscall and sysret.
This lets programs like `strace` exist.

# Radio System
> KOCOS.radio

Combines tunnels and modems under one unified interface.
Useful for network drivers.

Should also provide radio sockets.

# Keyboard System
> KOCOS.keyboard

Global keyboard interface that is very extra good.

Also TTY keyboard input via the aux port.

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

New `a` mode for the current write behavior.
Make `w` mode overwrite instead.
Add a `erase` syscall to erase bytes starting at the file position.

ManagedFS won't support `a` or `erase`.

# OKFFS optimizations

Smarter block allocator that is aware of platters.
Grouping writes to work smarter.
Reducing seek times.
