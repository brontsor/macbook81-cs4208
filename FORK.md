# Fork

Upstream is https://github.com/omnidecker/macbook8.1-speaker-driver
commit `e4134fb272ba3be29aa71ad7aa6eae8b0ebddf1a`. That repository
is a fork of
https://github.com/thomas-shirley/macbook8.1-speaker-driver.
Its README credits davidjo/snd_hda_macbookpro and
leifliddy/macbook12-audio-driver. leifliddy's driver does not
support MacBook8,1. Name that chain in the published README.

This tree is the installable fork. The DKMS package name is
`macbook81-cs4208`, version `0.1`. Version stays `0.1` until a
deliberate reinstall. The installed source link is
`/usr/src/macbook81-cs4208-0.1`. Bumping the version without that
reinstall points DKMS at a directory that does not exist.

`AUTOINSTALL=no` because the build downloads a kernel tarball. That
flag does not stop a pacman DKMS hook once `dkms.conf` is left in
`/usr/src`. Remove the link on uninstall. `dkms remove` alone can
leave it, and the hook builds every `dkms.conf` it finds.

The first release on top of the import is the headphone fix: the
`0x02`-only prepare, the jack switch that moves the playing stream,
and the output names. 48 kHz and 24-bit are not in this tree's
published files. Unfinished capture scripts live in `local/` and are
not published.

Kernel files in `patch_cirrus/` are GPL-2.0-or-later. `LICENSE` is
that text.

Do not install this beside `macbook12-audio`.
