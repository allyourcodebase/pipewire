# pipewire

Pipewire client library, ported to the Zig build system.

## Motivation

I want a static executable that can play audio and turn screen contents into a video feed.

## Status

I got the video-play example that displays the current webcam feed compiling and running (see `zig build video-play`.)

The pipewire library makes heavy use of `dlopen` internally, so further work will be needed to link statically to it.
