# OS Conventions

KOCOS is just a kernel. However, software targeting the kernel should also interact with the rest of the operating system.
Because of this, the software should know what to expect.

This document covers how an OS should be structured and to some extent work, such that software knows what to expect.
The kernel doesn't enforce much, and thus it isn't impossible to go against these conventions, but doing so may break some software.
It also covers how KPM's packages and repositories work, though the *exact* implementation details remain undefined.

Do note that the demo OS does not respect many of these conventions, this is because it is not meant to run most software.
If an OS does not need to run most software, not even via terminal emulators, then it can go against these conventions, as it
may not care about breaking other software.

OSs which may only care about supporting specific software may also implement these conventions only partially.

# Filesystem Structure

KOCOS will make `/dev` and `/tmp` be the devfs and tmpfs, however everything else is normally left up to the operating system.

The filesystem structure should be:
- `/dev`, for the devfs
- `/tmp`, for the tmpfs
- `/bin`, for the main binaries of the system
- `/bin/init` should be the init system's main binary. However, running it after a boot is undefined behavior.
- `/bin/sh` can be the shell path, though if it is changed, the SHELL environment variable should contain the full path to it. SHELL may also be specified
even if the path is `/bin/sh`, though if it is absent, programs can assume it is `/bin/sh`.
- `/lib` should contain libraries, each starting with `lib` and ending with either `.lua` if they're Lua source code, or `.so` if they're built binaries.
`require` should be able to load them, with `require("foo")` loading in `/lib/libfoo.so`'s `foo` module, and `require("foo.abc")` loading in `/lib/libfoo.so`'s
`foo.abc` module. It should contain `/lib/liblua.so`, and may also contain `/lib/libkelp.so`, or it may be provided by liblua.
- `/var` should contain files and folders expected to change while the system is running.
- `/var/log` should contain logfiles.
- `/var/lock` should contain lockfiles.
- `/etc` should contain configs and records to configure how the system works.
- `/usr/bin` should contain extra binaries. These are not required for the system to boot but can still be used as normal commands.
- `/usr/lib` should contain extra libraries. These are not required for the system to boot but can still be used as normal libraries.
- `/usr/exec` should contain internal binaries, which *should not be run by the user directly.* These may include sophisticated post-install steps,
or more complex removal tools.
- `/usr/man` should contain manual entries for documentation. It should contain files with no extensions, whos names are the manual entries passed to
programs such as `man`. It should be part of `MANPATH`. Any text wrapped in asterisks within those files should be highlighted in some way (either using
a brighter color or a different color altogether).
- `/home` should contain the home directories of all the users.
- `/etc/boot` should store a list of binaries used to boot the OS. The binaries are executed in sorted order, by the init system, on boot.
The init system may have other locations to define other boot locations. These binaries are executed with **no arguments** and **an empty environment**, at
**ring 0.** A conventional boot process would have one program which runs the main TTY and login (which are often merged into one program), and the rest just
start background daemons. The sorting used for the order is the default `table.sort` behavior when sorting the filenames. This also means that if the files
start with 3 digit numbers, as is convention, they will be ran in order of the numbers.
- `/mnt` should contain temporary mountpoints. `/mnt` itself may be the mountpoint, or it may simply contain the mountpoints.
- `/boot` should contain files necessary for booting. It may contain the kernel, and/or other files.

# Environment variables

When the *shell* is eventually launched by the login program, it should be given the following environment variables:
- `USER`, to state the human readable user ID of the current user. This name should also be the name of their corresponding directory in `/home`.
- `HOME`, as the path of the home directory.
- `CWD`, as the current working directory. This can be used by all programs.
- `SHELL`, as the shell of the user. This may not be very important to the shell itself, however programs which execute commands may do so with the shell.
- `PATH` is the path used to find shell binaries given command names. It should be a list of full paths to directories containing these files, separated
by `:`. When given command `x`, the shell should look in these directories for files `x`, `x.lua` and `x.kelp`. If there are multiple matches in these
directories for the same command, the file chosen is implementation-defined, and may be inconsistent.
- `MANPATH` works similarly to `PATH`, except that it stores directories to find manual entries.
- `MANPAGER` should be a program `man` can invoke to display the file. If it is empty, or set to an empty value, `man` should just print to stdout. The program
may be specified by full path, or by name searchable via `PATH`. It shall be invoked with one singular extra argument, the full path to the manual entry.
- `TERM`, as the *identifier* of the terminal emulator being used. This may be used by programs to use non-standard escape sequences or other operations
only supported by specific terminals.
- `COLORTERM`, as a string indicating the support for color. If the value is `nocolor`, then color codes are unsupported. If the value is `ansicolor`, then the
3-bit normal ANSI color escape sequences are supported. If the value is `256color`, then the 256-bit color escapes are supported. If the value is `truecolor`,
then the 24-bit color escapes are supported. This reports if it is supported by the terminal, though it should, to some extent, reflect hardware capabilities.
Whilst you should aim to use the directly supported color code, it is fair to assume that all *lower* versions are supported. For example, it is fair to use
ansi escape codes even if `COLORTERM` is `truecolor`.
- `LANG` should contain the locale intended to be used by programs, such as, `en_US.UTF-8`, which means "English (US), encoded in UTF-8." This may be used
by programs which support internationalization.

# Invoking the shell

When doing an `os.execute()`, it should invoke a shell.

It must call the shell, typically supplied in the `SHELL` environment variable, with a `-c` argument, and another argumet as the entire string of the command.
The invoked shell MUST immediately execute the command and exit with the same status code as the command. It MUST NOT continue running after the command.

# KPM

KPM has its config in `/etc/kpm.conf`, as a LON config.
The `repos` field should be a list of repositories.
Each repository should have a `type` and `repo` field, both of which are strings.

`type` may be `internet` for online repositories, and `filesystem` for on-disk repositories. More formats may be
supported by the implementation, but these 2 should exist.
For `internet` types, the `repo` is the full base URL, starting with `http://` or `https://`. To get the URLs of subfiles, `/subfilepath` is added to the end.
For `filesystem` types, the `repo` is the full path on disk to a directory. The subfiles are copied from there.

When downloading files over the `internet`, it makes plain GET requests. When using on-disk repositories, it copies the files.

When KPM queries package information, it will attempt to query, from all repositories, a `<package name>.kpm` file.

The package file should have the following fields, most of which are optional:
- `name`, a string representing the package's display name, which may difer from its filename. Defaults to the filename.
- `author`, a string representing the author of the package.
- `version`, a string representing the version of the package. Packages are only updated if the version string changes in any
way, not necessary as per semantic versioning, though it is recommended to use the `major.minor.patch` version naming scheme.
- `files`, a table where each field is a string representing the *full* path to put a file, and the value is the file path
local to this repository to download it from. If the parent directories are missing, they are created. Optional. Defaults to no files.
- `extraFiles`, a list of *full* paths to consider part of the package. These should be removed once uninstalled. These may be
directories, in which case they should be deleted recursively. Optional. Defaults to no extra files.
- `keepFiles`, a list of *full* paths to keep after uninstalling. Optional. Defaults to no kept files.
- `dependencies`, a list of packages to install as dependencies. Only package names are specified, and are queried through all repositories.
They should be installed before this package. Optional. Defaults to no dependencies.
- `addons`, a list of packages to *optionally* install, as dependencies. They may be rejected by the user.
- `postInstall`, a list of shell commands to `os.execute` after a first-install.
- `postUpdate`, a list of shell commands to `os.execute` after an update, but not on a first-install.
- `cleanup`, a list of shell commands to `os.execute` when the package is uninstalled, BEFORE any files are removed.
