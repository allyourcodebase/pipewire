# pipewire

Pipewire client library, statically linked, ported to the Zig build system.


## Motivation

I want a static executable that can play audio and turn screen contents into a video feed. The pipewire library makes heavy use of `dlopen` internally, so this is nontrivial.

## Strategy

This library builds pipewire with an alternate implementation of `dlfcn.h` (and some filesystem APIs) that look for data in a symbol table statically compiled with the executable, instead of loading the data at runtime.

For more information, see [src/wrap](src/wrap).

This project follows the pristine tarball approach. No modifications are required to the upstream pipewire source.

## Status

You can run the `video-play` example with `zig build video-play` to see the current webcam feed. This currently works without pipewire accessing the dynamic linker, but the example executable isn't fully static since it relies on SDL. I plan to port the example away from SDL so that this can be changed.

Only the pipewire plugins/modules required for this example are currently built. To use other parts of the pipewire API, you may need to add more symbols to [src/wrap/dlfcn.zig](src/wrap/dlfcn.zig).


## Usage

First, add pipewire to your `build.zig.zon`:
```sh
zig fetch --save git+https://github.com/allyourcodebase/pipewire
```

Then, link it to you executable in `build.zig`
```zig
const pipewire = b.dependency("pipewire", .{
    .optimize = optimize,
    .target = target,
});

// For Zig projects, add the `pipewire` module.
my_zig_exe.root_module.addImport("pipewire", pipewire.module("pipewire"));

// For C projects, link the `pipewire-0.3` static library.
my_c_exe.linkLibrary(pipewire.artifact("pipewire-0.3"));
```
