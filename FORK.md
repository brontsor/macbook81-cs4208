# Fork

This project starts from
https://github.com/omnidecker/macbook8.1-speaker-driver
commit `e4134fb272ba3be29aa71ad7aa6eae8b0ebddf1a`.

The DKMS package name in this tree is `macbook81-cs4208`, version `0.1`.
It is not `macbook12-audio`. Do not install it over that package.
`AUTOINSTALL` is `no` because the build downloads a kernel tarball.
That flag does not stop a pacman DKMS hook once a `dkms.conf` is left
in `/usr/src`. This tree is not in `/usr/src`.

Kernel files in `patch_cirrus/` are GPL-2.0-or-later, as marked.
`LICENSE` is that text.

The README below the fork note is the upstream README at that commit.
