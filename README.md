# pipewire

Pipewire client library, ported to the Zig build system.


## Motivation

I want a static executable that can play audio and turn screen contents into a video feed. The pipewire library makes heavy use of `dlopen` internally, so this is nontrivial.

## Status

You can run the `video-play` example with `zig build video-play` to see the current webcam feed. This currently works without pipewire accessing the dynamic linker, but the example executable uses SDL so it still has access to it. I plan to port the example away from SDL so that this can be changed.
