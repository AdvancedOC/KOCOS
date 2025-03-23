# KOCOS

Kernel for Open Computers Operating System

## Design

KOCOS is a monolithic-ish kernel, designed to be capable out of the box of managing many simple programs.

KOCOS provides a process system (with multi-threading and critical sections!), filesystem abstraction, TTY implementation, basic syscalls and event subsystems.

## Feature list

- High-level processes (with threads, environments, arguments, child processes)
- Per-resource event system
- Resource sharing via sharing file descriptors
- File descriptors to non-file resources
- Its own executable and linkable format (KOCOS Executable or Linkable Process / KELP)

## Project structure

`init.lua` is a basic template-OS using KOCOS. It is not a usable operating system in it of itself, but rather an example of what KOCOS can do.
`build.lua` is the build system. Running it will generate `kernel.lua`, a one-file concatenation of all of the source files of KOCOS.
The job of the BIOS is to run the bootloader of the OS, and the bootloader needs to run KOCOS and tell it to run the appropriate executable.
