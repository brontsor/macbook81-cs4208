# macbook81-cs4208

Internal speakers and headphone switching for the MacBook (Retina, 12-inch, Early 2015), model `MacBook8,1`, on Omarchy.

The codec is a Cirrus Logic CS4208. The speakers are a 4-channel TDM stream into an external amplifier, not the ordinary analog headphone DAC. Stock Linux detects the chip and does not play those speakers. This package does.

This is a fork of [omnidecker/macbook8.1-speaker-driver](https://github.com/omnidecker/macbook8.1-speaker-driver) at `e4134fb272ba3be29aa71ad7aa6eae8b0ebddf1a`, which is itself a fork of [thomas-shirley/macbook8.1-speaker-driver](https://github.com/thomas-shirley/macbook8.1-speaker-driver). That tree credits [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) and [leifliddy/macbook12-audio-driver](https://github.com/leifliddy/macbook12-audio-driver). leifliddy's driver does not support MacBook8,1. The package name is `macbook81-cs4208`, version `0.1`. It is not `macbook12-audio`. Do not install both. They ship the same three modules.

This fork fixes headphone reconnect. Upstream plays the speakers, and still calls jack switching wonky. A headphone open here no longer writes its stream onto the speaker converter, so plugging in does not kill the speakers. The jack switch is what moves a stream that is already playing. It does not restart WirePlumber. 48 kHz and 24-bit are not in this release. The speakers stay at 44.1 kHz, 16-bit.

## Install

Omarchy. From a clone of this repository:

```bash
sudo pacman -S --needed git base-devel dkms linux-omarchy-headers
sudo bash install.sh
sudo reboot
```

`install.sh` registers the DKMS package, installs the headphone jack watcher for the user who invoked sudo, and rebuilds the Limine UKI with `limine-mkinitcpio`. Do not run `limine-update`. That reinstalls the bootloader and is not this step.

If `macbook12-audio` is already installed, the script stops. Remove that package first. This script will not remove it for you.

After reboot, play real audio. Do not use `speaker-test`. Leave it playing, plug headphones in, unplug them, then plug them in again. That same stream should go to the headphones, back to the speakers, then to the headphones again. You should not have to switch the output by hand.

## Uninstall

```bash
sudo bash install.sh -r
sudo reboot
```

## What is installed

| Piece | Role |
|---|---|
| `snd-hda-intel` | Attaches to the live EFI link without a controller reset |
| `single_cmd=1` | Enumerates the codec on the immediate-command path |
| `snd-hda-codec-cs420x` | Writes the EFI coefficient image and the 44.1 kHz TDM prepare |
| `snd-hda-codec-generic` | Skips the input-path bring-up that latches the clock |
| `mb81-jack-switch` | On plug, moves the playing stream to the headphones and sets that as the default. On unplug, moves that stream back to the speakers. Plug in again and the same stream follows. Does not restart WirePlumber. |
| `mb81-resume-recover` | Workaround after a resume that leaves the amp dead |

Speaker names and the EQ chain are not this package. They are
`macbook81-audio-profile`. This installer does not copy them and does
not remove them.

The resume script is a workaround. It is not the headphone fix. A reboot is the clean fallback if resume audio is dead.

## Changes

The latest only. Older releases are in [CHANGELOG.md](CHANGELOG.md).

### [v0.1.2](https://github.com/brontsor/macbook81-cs4208/releases/tag/v0.1.2)

- The README states the headphone reconnect fix. A headphone open does not write its stream onto the speaker converter. The jack switch moves a stream that is already playing. It does not restart WirePlumber.
- 48 kHz and 24-bit are not in this release. The speakers stay at 44.1 kHz, 16-bit.
- A missing codec tarball fails the build. wget is tried first. If wget is absent, curl fetches the same tarball. A missing wget is not a missing tarball.
- `install.sh` does not rebuild the boot image, and does not print DONE, unless `dkms status` says `macbook81-cs4208/0.1` is installed for the running kernel.
- Tested on 12 October 2026 on a scratch MacBook (Retina, 12-inch, Early 2015), product name MacBook8,1, running the Omarchy Edge channel, kernel `7.2.8-5-omarchy-bore`. The loaded speaker module on that boot was this package.

## For agents

Read `AGENTS.md` before changing this tree. Read `FORK.md` for what this fork is and what it is not. Read `HOW_IT_WORKS.md` for the codec failure modes. `local/` is unfinished work and is not part of the install.

## License

Kernel sources in `patch_cirrus/` are GPL-2.0-or-later. See `LICENSE`.
