# Mclone

Mclone is a utility for offline file synchronization utilizing [Rclone](https://rclone.org) as a backend for doing
actual file transfer.

## Purpose

Suppose you have a (large amount of) data which needs to be either distributed across many storages or simply backed up.
Just consider a terabyte private media archive one can not afford to lose.

As the data gets periodically updated, there is a need for regular synchronization.
When the use of online cloud storage is not an option due storage space or security reasons, it is where  the good ol' offline
backing up comes back into play.

A sane backup strategy mandates the data copies to be physically separated - be it a next room (building, city or planet)
computer or just an external drive. Or, even better, the two computers' storages - the primary, where all activity takes place,
the mirror storage holding the backup, and a portable storage (USB flash disc, exteral HDD or SSD - whatever) which
serves as both an intermediate storage and a means of propagating the changes between the primary and the mirror.

In a more complex scenario there may be multiple one-way or two-way point-to-point data transfer routes between the storages,
employing portable storage as a "shuttle" or a "ferry".

All in all the synchronization task boils down to copying or synchronizing the contents of two local directories. However,
since portable storage is involved, the actual file paths may change between synchronizations as a storage device can be
mounted under different mount point on *NIX system or change the disk drive on Windows.

While the Rclone itself is a great tool for local file synchronization, typing the command line for execution in this case
becomes tedious and error prone where the possible cost of error is a backup corruption due to wrong paths or misspelled flags.

