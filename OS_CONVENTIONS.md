# OS Conventions

KOCOS is just a kernel. However, software targeting the kernel should also interact with the rest of the operating system.
Because of this, the software.

This document covers how an OS should be structured and to some extent work, such that software knows what to expect.
The kernel doesn't enforce much, and thus it isn't impossible to go against these conventions, but doing so may break some software.

Do note that the demo OS does not respect many of these conventions, this is because it is not meant to run most software.
If an OS does not need to run most software, not even via terminal emulators, then it can go against these conventions, as it
may not care about breaking other software.

## Filesystem Structure

KOCOS will make `/dev` and `/tmp` be the devfs and tmpfs, however everything else is normally left up to the operating system.

The filesystem structure should be:
- `/dev`, for the devfs
- `/tmp`, for the tmpfs
- `/bin`, for the main binaries of the system
- `/bin/init` should be the init system's main binary. However, running it after a boot is undefined behavior.
- `/bin/sh` can be the shell path, though if it is changed, the SHELL environment variable should contain the full path to it.
- `/lib` should contain libraries, each starting with `lib` and ending with either `.lua` if they're Lua source code, or `.so` if they're built binaries.
`require` should be able to load them, with `require("foo")` loading in `/lib/libfoo.so`'s `foo` module, and `require("foo.abc")` loading in `/lib/libfoo.so`'s
`foo.abc` module. It should contain `/lib/liblua.so`, and may also contain `/lib/libkelp.so`, or it may be provided by liblua.
- `/var` should contain files and folders expected to change while the system is running.
- `/var/log` should contain logfiles.
- `/var/lock` should contain lockfiles.
- `/etc` should contain configs and records to configure how the system works.
