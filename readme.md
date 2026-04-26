# osu-latency-tweaker

A wrapper for official osu-lazer on Linux, that reduces the audio latency of ALSA devices to absolute minimum (1-2 ms).

### How does this work?

Without getting into details:
it uses official osu-lazer appimage, extracts the files from the appimage, and finally patches the audio library file (libbass.so) used by osu to allow injecting custom audio initialization parameters.

### But why is this needed?

osu-lazer on Linux currently sets latency to 10ms-equivalent of period size (which equals to 441 samples @ 44100 hz), and 882 buffer size (twice the period size), for total of 20ms.
This is a "good default" meaning that it works on 99% of hardware.
But it on most modern hardware it's usually possible to go down to 128 (~2.8 ms) or even 64 samples (~1.4 ms).

When selected "Pipewire Server" in osu audio settings, this hardcoded 10ms is not a problem, because you can completely override it using a combination of `PIPEWIRE_ALSA` + `PIPEWIRE_QUANTUM` + `pw-cli s`/wireplumber (see https://github.com/ppy/osu-framework/issues/6647#issuecomment-4119317948 for instructions).

But when selecting your audio interface in osu settings, osu will grab that device for exclusive access (directly through ALSA).
This in principle is going to be more stable (less audio artifacts) than pipewire, and you might be able to set even lower latency while still being stable.
But unfortunately, in this case there are no external tweaks available such as env variables, and you're basically stuck to the hardcoded 10ms.
There was an attempt to add such env variable to osu ([See this PR](https://github.com/ppy/osu-framework/pull/6724)), but it didn't go though.
Now, this repo provides a hacky (but working) solution - provides a way to intercept calls that osu makes to libbass.so, which allows replacing the hardcoded 10 ms.

### Won't I get banned for using it?

Probably not.
It doesn't read or write memory at runtime.
It doesn't tamper with the main binary, only the BASS lib.
No warranties though.

Osu devs previously said that they don't want people replacing shipped binaries.
It's probably because it's inconvenient for them to get false crash reports by people and in telemetry for bugs caused by bad patches / replacements.
This should go without saying, but if you experience any issues while using the patches from this repo, especially crashes or audio issues - don't report them to osu repository, instead open an issue here.

### How to install / use it?

1. 1 dependency is required - Nix (build tool) - available to download from https://nixos.org/download/.
2. Run osu normally and select **An ALSA audio device from osu audio settings**. Anything that is not "Default" or "Pipewire Server" or "Pulse Audio" is ALSA device. **This is important**! Otherwise your audio will break.
3. Run without installation: `OSU_LATENCY_TWEAKER_FREQ=44100 OSU_LATENCY_TWEAKER_PERIOD=-441 NIXPKGS_ALLOW_UNFREE=1 nix run --extra-experimental-features 'nix-command flakes' --impure github:rszyma/osu-latency-tweaker`. This is just to see if it's working - it runs with the same latency params as osu.
4. If you confirm that it runs without issues, then read on, and tweak the environment variables to lower the latency. Pick first one from the table below that works for you without issues.

    Pick the highest frequency that your audio interface supports, and lowest period size that doesn't produce audio artifacts such a popping or crackling.
BTW, it doesn't make sense to me why higher sample rates in practice yield lower latency in osu, but measurements don't lie.

    **You should verify** that it indeed runs at requested frequency, otherwise it will just fallback to lower frequency with worse latency.
      - To verify, run: `cat /proc/asound/card*/pcm*/sub*/hw_params` while osu is running and check "rate" in the output.

   | Frequency | Setting | Latency (in theory<sup>2</sup>) | Latency (measured<sup>2</sup>) |
   |---|---|---:|---:|
   | 192000 Hz | `OSU_LATENCY_TWEAKER_FREQ=192000 OSU_LATENCY_TWEAKER_PERIOD=-256` | 2.7 ms | ~7.5 ms |
   | 192000 Hz | `OSU_LATENCY_TWEAKER_FREQ=192000 OSU_LATENCY_TWEAKER_PERIOD=-512` | 5.3 ms | — |
   | 192000 Hz | `OSU_LATENCY_TWEAKER_FREQ=192000 OSU_LATENCY_TWEAKER_PERIOD=-1024` | 10.7 ms | — |
   | 96000 Hz | `OSU_LATENCY_TWEAKER_FREQ=96000 OSU_LATENCY_TWEAKER_PERIOD=-128` | 2.7 ms | — |
   | 96000 Hz | `OSU_LATENCY_TWEAKER_FREQ=96000 OSU_LATENCY_TWEAKER_PERIOD=-256` | 5.3 ms | — |
   | 96000 Hz | `OSU_LATENCY_TWEAKER_FREQ=96000 OSU_LATENCY_TWEAKER_PERIOD=-512` | 10.7 ms | — |
   | 48000 Hz | `OSU_LATENCY_TWEAKER_FREQ=48000 OSU_LATENCY_TWEAKER_PERIOD=-64` | 2.7 ms | ~12 ms |
   | 48000 Hz | `OSU_LATENCY_TWEAKER_FREQ=48000 OSU_LATENCY_TWEAKER_PERIOD=-128` | 5.3 ms | — |
   | 48000 Hz | `OSU_LATENCY_TWEAKER_FREQ=48000 OSU_LATENCY_TWEAKER_PERIOD=-256` | 10.7 ms | — |

   <sup>1</sup> Calculated: `period_size / frequency * 1000 * 2` (2x because buffer size is 2x of period size)
   <br/>
   <sup>2</sup> Roundtrip latency of hitsounds on my system, from mouse click to capturing them with microphone. See [1][measurements-1],[2][measurements-2] for context.

   Note about `OSU_LATENCY_TWEAKER_PERIOD`: you may also set it to positive value e.g. `OSU_LATENCY_TWEAKER_PERIOD=5` for values in milliseconds, which will be auto-calculated into sample-size. For exact sample size set it to a negative value. Buffer size (which dictates final buffer latencies) is calculated for you underneath, and is always going to be 2x the period size.

1. (Optional) Now that the audio track is heard earlier, you may want to slightly adjust the global offset by a couple ms, to shift hit-objects to show faster too.

[measurements-1]: https://github.com/ppy/osu-framework/issues/6647#issuecomment-4114578725
[measurements-2]: https://github.com/ppy/osu-framework/issues/6647#issuecomment-4121944500

### Dev notes

Using `LD_PRELOAD` would be preferred (less invasive) than patching, and initially I wanted to use it, but couldn't make it work.
It just wouldn't replace the `BASS_Init` symbol.
At first I thought it was being blocked by osu code, but doesn't look like so.
It's not blocked by osu anticheat measures either, as it wouldn't work even with local osu builds.
