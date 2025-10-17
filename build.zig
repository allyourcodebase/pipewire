const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const valgrind_h_dep = b.dependency("valgrind_h", .{});
    const upstream = b.dependency("upstream", .{});

    const libpipewire = b.addLibrary(.{
        .name = "pipewire",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    libpipewire.addCSourceFiles(.{
        .root = upstream.path("src/pipewire"),
        .files = &.{
            "buffers.c",
            "conf.c",
            "context.c",
            "control.c",
            "core.c",
            "data-loop.c",
            "filter.c",
            "global.c",
            "impl-client.c",
            "impl-core.c",
            "impl-device.c",
            "impl-factory.c",
            "impl-link.c",
            "impl-metadata.c",
            "impl-module.c",
            "impl-node.c",
            "impl-port.c",
            "introspect.c",
            "log.c",
            "loop.c",
            "main-loop.c",
            "mem.c",
            "pipewire.c",
            "properties.c",
            "protocol.c",
            "proxy.c",
            "resource.c",
            "settings.c",
            "stream.c",
            "thread-loop.c",
            "thread.c",
            "utils.c",
            "work-queue.c",
        },
        .flags = &.{
            "-fvisibility=hidden",
            "-fno-strict-aliasing",
            "-Wno-missing-field-initializers",
            "-Wno-unused-parameter",
            "-Wno-pedantic",
            "-D_GNU_SOURCE",
            "-DFASTPATH",
        },
    });
    libpipewire.addIncludePath(valgrind_h_dep.path(""));
    libpipewire.addIncludePath(upstream.path("spa/include"));
    libpipewire.addIncludePath(upstream.path("src"));

    const version_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/pipewire/version.h.in") },
        .include_path = "pipewire/version.h",
    }, .{
        .PIPEWIRE_VERSION_MAJOR = 1,
        .PIPEWIRE_VERSION_MINOR = 1,
        .PIPEWIRE_VERSION_MICRO = 82,
        .PIPEWIRE_API_VERSION = "0.3",
    });
    libpipewire.addConfigHeader(version_h);

    const config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "config.h",
    }, .{
        .GETTEXT_PACKAGE = "pipewire",
        .HAVE_ALSA_COMPRESS_OFFLOAD = {},
        .HAVE_GETRANDOM = {},
        .HAVE_GETTID = {},
        .HAVE_GRP_H = {},
        .HAVE_GSTREAMER_DEVICE_PROVIDER = {},
        .HAVE_MALLOC_INFO = {},
        .HAVE_MALLOC_TRIM = {},
        .HAVE_MEMFD_CREATE = {},
        .HAVE_PIDFD_OPEN = {},
        .HAVE_PWD_H = {},
        .HAVE_RANDOM_R = {},
        .HAVE_REALLOCARRAY = {},
        .HAVE_SIGABBREV_NP = {},
        .HAVE_SPA_PLUGINS = 1,
        .HAVE_SYS_MOUNT_H = {},
        .HAVE_SYS_PARAM_H = {},
        .HAVE_SYS_RANDOM_H = {},
        .HAVE_SYS_VFS_H = {},
        .LIBDIR = "/usr/local/lib",
        .LOCALEDIR = "/usr/local/share/locale",
        .MODULEDIR = "/usr/local/lib/pipewire-0.3",
        .PACKAGE = "pipewire",
        .PACKAGE_NAME = "PipeWire",
        .PACKAGE_STRING = "PipeWire 1.1.82",
        .PACKAGE_TARNAME = "pipewire",
        .PACKAGE_URL = "https://pipewire.org",
        .PACKAGE_VERSION = "1.1.82",
        .PA_ALSA_DATA_DIR = "/usr/local/share/alsa-card-profile/mixer",
        .PIPEWIRE_CONFDATADIR = "/usr/local/share/pipewire",
        .PIPEWIRE_CONFIG_DIR = "/usr/local/etc/pipewire",
        .PLUGINDIR = "/usr/local/lib/spa-0.2",
        .PREFIX = "/usr/local",
        .RTPRIO_CLIENT = 83,
        .RTPRIO_SERVER = 88,
        .SPADATADIR = "/usr/local/share/spa-0.2",
    });
    libpipewire.addConfigHeader(config_h);
    libpipewire.installConfigHeader(version_h);
    libpipewire.linkLibC();
    libpipewire.installHeadersDirectory(upstream.path("spa/include"), "", .{});
    libpipewire.installHeadersDirectory(upstream.path("src"), "", .{});
    b.installArtifact(libpipewire);

    const audio_src_exe = b.addExecutable(.{
        .name = "audio-src",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    audio_src_exe.addCSourceFiles(.{
        .root = upstream.path("src/examples"),
        .files = &.{"audio-src.c"},
    });
    audio_src_exe.linkLibrary(libpipewire);
    b.installArtifact(audio_src_exe);
}
