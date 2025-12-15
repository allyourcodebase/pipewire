# pipewire

Pipewire client library, statically linked, ported to the Zig build system.


## Motivation

I want a static executable that can play audio and turn screen contents into a video feed. The pipewire library makes heavy use of `dlopen`  internally, so this is nontrivial.

## Strategy

This library builds pipewire with an alternate implementation of `dlfcn.h` (and some filesystem APIs) that look for data in a symbol table statically compiled with the executable, instead of loading the data at runtime.

For more information, see [src/wrap](src/wrap).

This project follows the pristine tarball approach. No modifications are required to the upstream pipewire source.

## Examples

You can run `zig build audio-src` to play a sine wave, and `zig build video-play` to see the current webcam feed. Use something like `-Dtarget=x86_64-linux-musl` if you want full static linking.

Note that the video feed will be fairly low resolution as the example doesn't have a real graphics stack and as such is rendering pixels one at a time. It also only supports the YUV2 video format.

## Status

Only the pipewire plugins/modules required for the provided examples are currently built. To use other parts of the pipewire API, you may need to add more symbols to the `libs` table in [src/wrap/dlfcn.zig](src/wrap/dlfcn.zig) and regenerate `c.zig` if additional pipewire headers are required. Contributions welcome!

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

You can then access pipewire as you would normally from C, you can import the already translated headers from Zig. This is necessary for now as the headers can't yet be translated automatically, in the future you'll be able to use `@cImport` directly:
```zig
const pw = @import("pipewire").c;

pw.pw_init(0, null);
defer pw.pw_deinit();

// ...
```

See [`src/examples`](`src/examples`) for more information.

### Help, I'm getting undefined symbols!

If you import the Pipewire zig module but don't reference it, the import won't get evaluated and the wrapper functions won't get exported.

To resolve this, use something from the pipewire module, or declare `comptime { _ = @import("pipewire"); }` to force evaluation.
