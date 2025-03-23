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
