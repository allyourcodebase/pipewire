# pipewire

Pipewire client library, ported to the Zig build system.

## Motivation

I want a static executable that can play audio. I have this working already
with libsoundio, however, it is via the pulseaudio client library. I thought it
would be nice to use pipewire directly on systems that use it.

## Status

I got the audio-src example compiling and running, however, it turns out the
pipewire protocol only works via `dlopen`, making it a non-starter for static
executables.

Therefore, I will not be pursuing this project any further.
