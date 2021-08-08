# Mclone

[Mclone](https://github.com/okhlybov/mclone) is a utility for offline file synchronization utilizing the
[Rclone](https://rclone.org) as a backend for doing actual file transfer.

## Purpose

Suppose you have a (large amount of) data which needs to be either distributed across many storages or simply backed up.
For example, consider a terabyte private media archive one can not afford to lose.

As the data gets periodically updated, there is a need for regular synchronization.
When the use of online cloud storage is not an option due storage space or security reasons, the good ol' offline
backing up comes back into play.

A sane backup strategy mandates the data copies to be physically separated - be it a next room (building, city or planet)
computer or just an external drive. Or, even better, the two computers' storages - a primary, where all activity takes place,
a mirror storage which holds the backup, and a portable storage (USB flash disc, external HDD or SSD - whatever) which
serves as both an intermediate storage and a means of propagating the changes between the primary and the mirror.

In a more complex scenario there may be multiple one-way or two-way point-to-point data transfer routes between the storages,
employing portable storage as a "shuttle" or a "ferry".

All in all the synchronization task boils down to copying or synchronizing the contents of two local directories. However,
since portable storage is involved, the actual file paths may change between synchronizations as a storage can be
mounted under different mount points on *NIX system or change the disk drive on Windows system.

While the Rclone itself is a great tool for local file synchronization, typing command line to be executed in this case
becomes tedious and error prone where possible cost of error is a backup corruption due to wrong paths or misspelled flags.

This is where the Mclone comes in.
It is designed to automatize the Rclone synchronization process by memorizing command line options and detecting
proper source and destination locations wherever they are.

## Installation

Mclone is written in [Ruby](https://www.ruby-lang.org) language and is distributed in the form of the Ruby [GEM](https://rubygems.org).

Once the Ruby runtime is properly set, the Mclone itself is installed with

```shell
$ gem install mclone
```

Obviously, the Rclone installation is also required.
The Mclone will use either the contents of the `RCLONE` environment variable if exists or look though
the `PATH` environment variable to locate the `rclone` executable.

Once properly installed, the Mclone provides the `mclone` command line utility.

```shell
$ mclone -h
```
## Basic use case

Let's start with the simplest case.

Suppose you have a data directory `/data` and you'd want to set up the backup of the `/data/files` subdirectory
into a backup directory `/mnt/backup`. The latter may be an ordinary directory or a mounted portable storage, or whatever.

### 1. Create volumes

Mclone has a notion of a volume - a file system directory containing the `.mclone` file, which is used as a root directory
for all Mclone operations.

By default, in order to detect currently available volumes the Mclone scans all mount points on *NIX systems and
all available disk drives on Windows system. Additionally, a static volume directories list to consider can be specified
in the `MCLONE_PATH` environment variable which is a PATH-like list of directories separated by the double colon `:`
on *NIX systems or the semicolon `;` on Windows system.

If the `/data` is a regular directory, it won't be picked up by the Mclone automatically, so it needs to be put into
the environment for later reuse

```shell
export MCLONE_PATH=/data
```

On the other hand, if the `/mnt/backup` is a mount point for a portable storage, it will be autodetected,
therefore there is no need to put it there.

Both source and destination endpoints have to "formatted" in order to be recognized as the Mclone volumes

```shell
$ mclone volume create /data
$ mclone volume create /mnt/backup
```

After that, `mclone info` can be used to review the recognized volumes

```shell
$ mclone info

# Mclone version 0.1.0

## Volumes

* [6bfa4a2d] :: (/data)
* [7443e311] :: (/mnt/backup)
```

Each volume is identified by the randomly generated tag shown within the square brackets `[...]`.
_Obviously, the tags will be different in your case._

### 2. Create a task

A Mclone task corresponds to a single Rclone command. It contains the source and destination volume identifiers,
the source and destination subdirectories _relative to the respective volumes_,
as well as additional Rclone command line arguments to be used.

_There can be multiple tasks linking different source and destination volumes as well as their respective subdirectores._

A task with all defaults is created with

```shell
$ mclone task create /data/files /mnt/backup/files
```

Note that at with point there is no need to use the above volume tags as they will be auto-determined during task creation.

Again, use the `mclone info` to review the changes

```shell
# Mclone version 0.1.0

## Volumes

* [6bfa4a2d] :: (/data)
* [7443e311] :: (/mnt/backup)

## Intact tasks

* [cef63f5e] :: update [6bfa4a2d](files) -> [7443e311](files) :: include **
```

The output literally means: ready to process (intact) update `cef63f5e`  task from the `files` source subdirectory of the
`6bfa4a2d`  volume to the `files` destination subdirectory of the `7443e311`  volume
including `**` all files and subdirectories.

Again, the task's tag is randomly generated and will be different in your case.

There are two kinds of tasks to encounter - intact and stale.

An intact task is a task which is fully ready for processing with the Rclone.
As with the volumes, its tag is shown in the square brackets `[...]`

Conversely, a stale task is not ready for processing due to currently missing source or destination volume.
A stale task's tag is shown in the angle brackets `<...>`. Also, a missing stale task's volume tag will also be shown in
the angle brackets.

Thank to the indirection in the source and destination directories, **this task will be handled properly regardless of the
portable storage directory it will be mounted in next time provided that it will be detectable by the Mclone**.

The same applies to the Windows system where the portable storage can be appear as different disk drives and yet
be detectable by the Mclone.

### 3. Modify the task

Once a task is created, its source and destination volumes and directories get fixed and can not be changed.
Therefore the only way to modify it is to start from scratch preceded by the task deletion with the `mclone task delete` command.

A task's optional parameters however can be modified afterwards with the `mclone task modify` command.

Suppose you'd want to change the operation mode from default updating to synchronization and exclude `.bak` files.

```shell
$ mclone task modify -m sync -x '*.bak' cef
```

This time the task is identified by its tag instead of a directory.

Note the mode and task's tag abbreviations: `synchronize` is reduced to `sync` (or it can be cut down further to `sy`)
and the tag is reduced from full `cef63f5e` to `cef` for convenience and type saving.
Any part of the full word can be used as an abbreviation provided it is unique among all other full words of the same kind
otherwise the Mclone will bail out with error.

The abbreviations are supported for operation mode, volume and task tags.

Behold the changes

```shell
$ mclone info

# Mclone version 0.1.0

## Volumes

* [6bfa4a2d] :: (/data)
* [7443e311] :: (/mnt/backup)

## Intact tasks

* [cef63f5e] :: synchronize [6bfa4a2d](files) -> [7443e311](files) :: include ** :: exclude *.bak
```

### 4. Process the tasks

Once created all intact tasks can be (sequentially) processed with the `mclone task process` command.

```shell
$ mclone task process
```

If specific tasks need to be processed, their (possibly abbreviated) tags are specified as command line arguments


```shell
$ mclone task process cef
```

Technically, for a task to be processed the Mclone renders the full source and destination path names from the respective
volume locations and relative paths and passes them along with other options to the Rclone to do the actual processing.

Thats it. No more need to determine (and type in) current locations of the backup directory and retype all those Rclone arguments
for every occasion.

## Advanced use case

Now back to the triple storage scenario outlined above.

Let **S** be a source storage from where the data needs to be backed up, **D** be a destination storage where the data is to
be mirrored and **P** be a portable storage which serves as both an intermediate storage and a means of the **S->D** data propagation.

In this case the full data propagation graph is **S->P->D**.

### 1. Set up the S->P route

1.1. Plug in the **P** portable storage to the **S**'s computer and mount it.

1.2. As shown in the basic use case, create **S**'s and **P**'s volumes, then create a **S->P** task.

1.3. Unplug **P**.

At this point **S** and **P** are now separated and each carry its own copy of the **S->P** task.

### 2. Set up the P->D route

2.1. Plug in the **P** portable storage to the **D**'s computer and mount it.

Note that at this point the **S->P** is a stale task as **D**'s computer knows nothing about **S** storage.

2.2. Create the **D**'s volume, then create a **P->D** task.
Note that **P** at this point already contains a volume and therefore must not be formatted.

2.3. Unplug **P**.

Now **S** and **D** are formatted and carry the respective tasks.
**P** contains its own copies of both **S->P** and **P->D** tasks.

### 3. Process the **S->P->D** route

3.1. Plug in **P** to the **S**'s computer and mount it.

3.2. Process the intact tasks. In this case it is the **S->P** task (**P->D** is stale at this point).

3.3. Unplug **P**.

**P** now carries its own copy of the **S**'s data.

3.4. Plug in **P** to the **D**'s computer and mount it.

3.5. Process the intact tasks. In this case it is the **P->D** task (**S->P** is stale at this point).

3.6. Unplug **P**.

_Voilà!_
Both **P** and **D** now carry a copy of the **S**'s data.

There may be more complex data propagation scenarios with  multiple source and destination storages utilizing the portable
storage in the above way.

Consider a two-way synchronization between two storages with a portable ferry which carries and propagates data in both directions.

## Encryption

Encryption is an essential part of the Mclone as it is all about handling portable storage which may by compromised
while holding confidential data. Mclone fully relies on [encryption capabilities](https://rclone.org/crypt/) of Rclone,
that is an encrypted directory structure can be further treated with the Rclone itself.

The encryption operation in Mclone is activated during task creation time.
The encryption mode is activated with `-e` or `-d` command line flag for encryption or decryption, respectively.
It no either flag is specified, the encryption gets turned off.

When in encryption mode, Mclone recursively takes plain files and directories under the source root and creates encrypted
files and directories under the destination root.
Conversely, when in decryption mode, Mclone takes encrypted source root and decrypts it into the destination root.
Mclone is set up to encrypt not only the files' contents but also the file and directory names themselves. The file sizes,
modification times as well as some other metadata are not encrypted, though, as they are required for proper operation 
the file synchronization mechanism.
Note that the encrypted root is a regular directory hierarchy (just with fancy file names) and thus can be treated as such.

***Be wary that file name encryption has a serious implication on the file name length.***
The Rclone [crypt](https://rclone.org/crypt/) documentation states the the individual file or directory name length can
not exceed ~143 charactes (although ***bytes*** here would be more correct).
As the Rclone accepts UTF-8 encoded names, this estimate generally holds true for the Latin charset only, where
a character is encoded with a single byte.
For non-Latin characters, which can be encoded with two or even more bytes, the maximum allowed name length be
much lower.
When Rclone encounters a file name too long to hold, it will refuse to process it.

Rclone employs symmetric cryptography to do its job, which requires some form of password to be supplied upon task
creation.
This is done by the `-p` command line flag, which specifies a plain text password used to derive the real encryption key.
There is another password-related `-t` command line flag which can be used to directly specify
an [Rclone-obscured](https://rclone.org/commands/rclone_obscure/) token.
Once created, a task memorizes the encryption key on the ***unencrypted end*** of the source/destination volume pair,
so there will be no need to pass it during the task processing.

## Whats next

### On-screen help

Every `mclone` (sub)command has its own help page which can be shown with `--help` option

```shell
$ mclone task create --help

Usage:
    mclone task new [OPTIONS] SOURCE DESTINATION

Parameters:
    SOURCE                     Source path
    DESTINATION                Destination path

Options:
    -m, --mode MODE            Operation mode (update | synchronize | copy | move) (default: "update")
    -i, --include PATTERN      Include paths pattern
    -x, --exclude PATTERN      Exclude paths pattern
    -d, --decrypt              Decrypt source
    -e, --encrypt              Encrypt destination
    -p, --password PASSWORD    Plain text password
    -t, --token TOKEN          Rclone crypt token (obscured password)
    -f, --force                Insist on potentially dangerous actions (default: false)
    -n, --dry-run              Simulation mode with no on-disk modifications (default: false)
    -v, --verbose              Verbose operation (default: false)
    -V, --version              Show version
    -h, --help                 print help
```

### File filtering

The Mclone passes its include and exclude options to the Rclone.
The pattern format is an extended glob (`*.dat`) format described in detail in the corresponding Rclone
documentation [section](https://rclone.org/filtering).

### Dry run

The Mclone respects the Rclone's dry run mode activated with `--dry-run` command line option in which case
no volume (`.mclone`) files are ever touched (created, overwritten) during any operation.
The Rclone is run during task processing but in turn is supplied with this option.

### Force mode

The Mclone will refuse to automatically perform certain actions which are considered dangerous, such as deleting a volume
or overwriting existing task.
In this case a `--force` command line option should be used to pass through.

### Task operation modes

#### Update

* Copy source files which are newer than the destination's or have different size or checksum.

* Do not delete destination files which are nonexistent in the source.

* Do not copy source files which are older than the destination's.

A default refreshing mode which is considered to be least harmful with respect to the unintentional data override.

Rclone [command](https://rclone.org/commands/rclone_copy): `copy --update`.

#### Synchronize

* Copy source files which are newer than the destination's or have different size or checksum.

* Delete destination files which are nonexistent in the source.

* Copy source files which are older than the destination's.

This is the mirroring mode which makes destination completely identical to the source.

Rclone [command](https://rclone.org/commands/rclone_sync): `sync`.

#### Copy

* Copy source files which are newer than the destination's or have different size or checksum.

* Do not delete destination files which are nonexistent in the source.

* Do not copy source files which are older than the destination's.

This mode is much like synchronize with only difference that it does not delete files.

Rclone [command](https://rclone.org/commands/rclone_copy): `copy`.

#### Move

* Copy source files which are newer than the destination's or have different size or checksum.

* Do not delete destination files which are nonexistent in the source.

* Do not copy source files which are older than the destination's.

* Delete source files after successful copy to the destination.

Rclone [command](https://rclone.org/commands/rclone_move): `move`.

## The end

Cheers,

Oleg A. Khlybov <fougas@mail.ru>