# Radio System
> KOCOS.radio

Combines tunnels and modems under one unified interface.
Useful for network drivers.

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

# Domain Sockets

A new "domain" protocol with the "channel" subprotocol.
These communicate via IPC, where the address is a key into a big table.

# Chown syscall

A simple syscall to change a permission at a path.
Requires write permissions for that path.

# OKFFS mode changes

New `a` mode for the current write behavior.
Make `w` mode overwrite instead.
Add a `erase` syscall to erase bytes starting at the file position.

ManagedFS won't support `a` or `erase`.
