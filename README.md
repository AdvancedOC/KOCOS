# KOCOS

Kernel for Open Computers Operating System

## Design

KOCOS is a monolithic-ish kernel, designed to be capable out of the box of managing many simple programs.
With all features compiled in, it is a heavy kernel, and has high system requirements. Things can be compiled out though.

KOCOS provides a process system (with multi-threading and critical sections!), filesystem abstraction, TTY implementation, UNIX-inspired syscalls and event
subsystems.

## Feature list

- High-level processes (with threads, environments, arguments, child processes)
- Per-resource event system
- Resource sharing via sharing file descriptors
- File descriptors to non-file resources
- Router system. No drivers for any protocols are built-in, but the router system supports custom drivers.
- Its own executable and linkable format (KOCOS Executable or Linkable Process / KELP)
- Berkeley-ish sockets. (though `listen` is renamed to `serve`, as `listen` is used to setup signal callbacks)
- Domain sockets
- Radio interface, and radio sockets, to simplify communicating over modems and tunnels (radio sends strings with modems and strings and port number
with tunnels)
- Support for custom *drivers*, which can also be loaded by ring 0 and ring 1 processes, which get direct access to the kernel.
- File system permissions support (NOTE: managed filesystems has all permissions enabled on all paths currently)
- DevFS
- Unmanaged filesystem support, with built-in support for GPT partitions, MTPT partitions, and OKFFS file systems (custom format).
- Virtual Machine support via KVM, with support for a custom `kocos` component, which allows TTY sharing and requesting passthrough at runtime. It also
supports mounting filesystem paths as virtual `filesystem` components.
- Hostname support

## Project structure

`init.lua` is a basic template-bootloader using KOCOS. It is not a proper bootloader, but is enough for the demo OS.
`basicTTY.lua` is the demo OS' single process. It is a shell (confusingly), and has all the commands as built-ins.
`build.lua` is the Kernel's build system. Running it will generate `kernel.lua`, a one-file concatenation of all of the source files of KOCOS.
`build_libs.lua` is the library's build system. Running it will generate the binaries in `/lib`. These libraries are not just useful for operating systems,
but are also needed by the demo OS.
`luart` is a prebuilt binary needed for the `lua` command. It is a hack to link in `/lib/liblua.so` and run a Lua script.

## Non-POSIX characteristics

In KOCOS, `stdout` is 0, `stdin` is 1 and `stderr` is 2. This means `stdout` and `stdin` are swapped compared to most POSIX OSes.
Compared to `UlOS` specifically, KOCOS syscalls are handled via the `syscall` function passed in, as opposed to coroutine yields (this makes them faster).
The TTY supports many ANSI escapes, though keyboard input uses custom escapes, and the ANSI Auxiliary port is reserved for immediate keyboard mode,
as opposed to using any kind of `ioctl`. This is to make communicating with the TTY only require *transmitting strings*, which makes it trivial to
stream them over in-memory files, thus this approach was chosen as opposed to more common approaches.

# Boot process
The job of the BIOS is to run the bootloader of the OS, and the bootloader needs to run KOCOS and tell it to run the appropriate executable via the kernel
arguments. Kernel arguments are a table passed in as the first argument when calling the kernel. `init` is the path to run as the init process.
