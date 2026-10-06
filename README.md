# macbook81-cs4208

Internal speakers and headphone switching for the MacBook (Retina, 12-inch, Early 2015), model `MacBook8,1`, on Omarchy.

The codec is a Cirrus Logic CS4208. The speakers are a 4-channel TDM stream into an external amplifier, not the ordinary analog headphone DAC. Stock Linux detects the chip and does not play those speakers. This package does.

This is a fork of [omnidecker/macbook8.1-speaker-driver](https://github.com/omnidecker/macbook8.1-speaker-driver) at `e4134fb272ba3be29aa71ad7aa6eae8b0ebddf1a`. The package name is `macbook81-cs4208`, version `0.1`. It is not `macbook12-audio`. Do not install both. They ship the same three modules.

This release adds the headphone fix. A headphone open no longer writes its stream onto the speaker converter, and unplugging the jack moves the playing stream back to the speakers. It does not restart WirePlumber. 48 kHz and 24-bit are not in this release. The speakers stay at 44.1 kHz, 16-bit.

## Install

Omarchy. From a clone of this repository:

```bash
sudo pacman -S --needed git base-devel dkms linux-omarchy-headers
sudo bash install.sh
sudo reboot
```

`install.sh` registers the DKMS package, installs the PipeWire and WirePlumber configs for the user who invoked sudo, installs the headphone jack watcher, and rebuilds the Limine UKI with `limine-mkinitcpio`. Do not run `limine-update`. That reinstalls the bootloader and is not this step.

If `macbook12-audio` is already installed, the script stops. Remove that package first. This script will not remove it for you.

After reboot, play real audio through `input.MacBook_Speaker`. Do not use `speaker-test`. Plug and unplug headphones while something is playing. The stream should move both ways, and the menu should not be required.

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
| PipeWire / WirePlumber configs | EQ sink and the raw speaker node |
| `mb81-jack-switch` | Moves the playing stream when the headphone jack changes |
| `mb81-resume-recover` | Workaround after a resume that leaves the amp dead |

The resume script is a workaround. It is not the headphone fix. A reboot is the clean fallback if resume audio is dead.

## For agents

Read `AGENTS.md` before changing this tree. Read `FORK.md` for what this fork is and what it is not. Read `HOW_IT_WORKS.md` for the codec failure modes. `local/` is unfinished work and is not part of the install.

## License

Kernel sources in `patch_cirrus/` are GPL-2.0-or-later. See `LICENSE`.
