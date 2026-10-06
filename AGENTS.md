# macbook81-cs4208

Installable speaker package for MacBook8,1 on Omarchy. Package name
`macbook81-cs4208`, version `0.1`.

- Do not install this beside `macbook12-audio`. Both ship
  `snd-hda-codec-cs420x`, `snd-hda-codec-generic`, and `snd-hda-intel`.
- Install with `sudo bash install.sh`, then reboot. On Omarchy the
  installer runs `limine-mkinitcpio`. Do not run `limine-update`.
- The headphone fix is two pieces, and both are in this package. The
  codec piece is the `0x02`-only prepare in `patch_cirrus/cs420x.c`.
  The route piece is `mb81-jack-switch.sh`, installed as a user
  service. It moves the playing stream. It does not restart
  WirePlumber, write a coefficient, or touch GPIO.
- Speaker names and the EQ chain are not this package. They are
  `macbook81-audio-profile`. Do not copy those files back into this
  installer.
- Do not add `SNDRV_PCM_RATE_48000` by itself. 48 kHz and 24-bit are
  not in this release. No GPIO4. No GPIO5.
- `local/` is gitignored. It is unfinished capture work. Do not commit
  it, and do not describe it as part of the install.
- Playback checks use real audio. Do not use `speaker-test`. Do not
  raise the volume for a first listen.
- Do not push or add a remote unless asked.
- A decision that should outlive a session goes on the workshop audio
  page, not in a recap here.
