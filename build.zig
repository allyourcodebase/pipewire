const std = @import("std");
const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    // Get the target and optimize options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const host_target = b.resolveTargetQuery(.{});
    const host_optimize = .Debug;

    const rtprio_client = b.option(u8, "rtprio_client", "PipeWire clients realtime priority") orelse 83;
    if (rtprio_client < 11 or rtprio_client > 99) @panic("invalid rtprio_client");

    const rtprio_server = b.option(u8, "rtprio_server", "PipeWire server realtime priority") orelse 88;
    if (rtprio_server < 11 or rtprio_server > 99) @panic("invalid rtprio_server");

    // Get the upstream sources
    const upstream = b.dependency("upstream", .{});

    // Create a custom installation directory. This is exposed to end users, so that they can
    // install pipewire's dependencies alongside their executable.
    const install_dir = b.addNamedWriteFiles("pipewire-0.3");
    b.installDirectory(.{
        .install_dir = .lib,
        .source_dir = install_dir.getDirectory(),
        .install_subdir = "pipewire-0.3",
    });

    // Compile our dl stub
    const dl = b.addLibrary(.{
        .name = "dl",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Build and install the configuration
    {
        const generate_conf = b.addExecutable(.{
            .name = "generate_conf",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/generate_conf.zig"),
                .target = host_target,
                .optimize = host_optimize,
            }),
        });

        const options = b.addOptions();
        options.addOption([]const u8, "VERSION", b.fmt("\"{s}\"", .{build_zon.version}));
        options.addOption([]const u8, "PIPEWIRE_CONFIG_DIR", "[install path]");
        options.addOption([]const u8, "rtprio_client", b.fmt("{}", .{rtprio_client}));
        generate_conf.root_module.addOptions("options", options);

        const run_generate_conf = b.addRunArtifact(generate_conf);
        run_generate_conf.addFileArg(upstream.path("src/daemon/client.conf.in"));
        const client_conf = run_generate_conf.addOutputFileArg("client.conf");

        _ = install_dir.addCopyFile(client_conf, b.pathJoin(&.{ "confdata", "client.conf" }));
    }

    // Build the configuration headers
    const pipewire_version = std.SemanticVersion.parse(build_zon.version) catch
        @panic("invalid version");
    const version_h = b.addConfigHeader(.{
        .style = .{ .cmake = upstream.path("src/pipewire/version.h.in") },
        .include_path = "pipewire/version.h",
    }, .{
        .PIPEWIRE_VERSION_MAJOR = @as(i64, @intCast(pipewire_version.major)),
        .PIPEWIRE_VERSION_MINOR = @as(i64, @intCast(pipewire_version.minor)),
        .PIPEWIRE_VERSION_MICRO = @as(i64, @intCast(pipewire_version.patch)),
        .PIPEWIRE_API_VERSION = build_zon.api_version,
    });

    const config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "config.h",
    }, .{
        .GETTEXT_PACKAGE = "pipewire",
        .HAVE_ALSA_COMPRESS_OFFLOAD = {},
        .HAVE_DBUS = {},
        .HAVE_GETRANDOM = {},
        .HAVE_GETTID = {},
        .HAVE_GIO = {},
        .HAVE_GLIB2 = {},
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
        .HAVE_SPA_PLUGINS = {},
        .HAVE_SYS_AUXV_H = {},
        .HAVE_SYS_MOUNT_H = {},
        .HAVE_SYS_PARAM_H = {},
        .HAVE_SYS_RANDOM_H = {},
        .HAVE_SYS_VFS_H = {},
        .LIBDIR = "pipewire-0.3",
        .LOCALEDIR = "pipewire-0.3",
        .MODULEDIR = "pipewire-0.3/modules",
        .PACKAGE = "pipewire",
        .PACKAGE_NAME = "PipeWire",
        .PACKAGE_STRING = b.fmt("PipeWire {s}", .{build_zon.version}),
        .PACKAGE_TARNAME = "pipewire",
        .PACKAGE_URL = "https://pipewire.org",
        .PACKAGE_VERSION = build_zon.version,
        .PIPEWIRE_CONFDATADIR = "pipewire-0.3/confdata",
        .PIPEWIRE_CONFIG_DIR = "pipewire-0.3",
        .PLUGINDIR = "pipewire-0.3/plugins",
        .RTPRIO_CLIENT = rtprio_client,
        .RTPRIO_SERVER = rtprio_server,
    });

    // Build libpipewire
    const libpipewire = b.addLibrary(.{
        .name = "pipewire-0.3",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    libpipewire.linkLibrary(dl);
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
            "timer-queue.c",
            "utils.c",
            "work-queue.c",
        },
        .flags = flags,
    });
    libpipewire.linkLibC();

    libpipewire.addIncludePath(b.dependency("valgrind_h", .{}).path(""));
    libpipewire.addIncludePath(upstream.path("spa/include"));
    libpipewire.addIncludePath(upstream.path("src"));
    libpipewire.addConfigHeader(version_h);
    libpipewire.addConfigHeader(config_h);

    libpipewire.installHeadersDirectory(upstream.path("src/pipewire"), "pipewire", .{});
    libpipewire.installHeadersDirectory(upstream.path("spa/include/spa"), "spa", .{});
    libpipewire.installConfigHeader(version_h);

    b.installArtifact(libpipewire);

    // Build the plugins and modules
    {
        const pm_ctx: PluginAndModuleCtx = .{
            .upstream = upstream,
            .target = target,
            .optimize = optimize,
            .version = version_h,
            .config = config_h,
            .install_dir = install_dir,
            .libpipewire = libpipewire,
        };

        // Build and install the plugins
        _ = PipewirePlugin.build(b, pm_ctx, .{
            .name = "support",
            .files = &.{
                "cpu.c",
                "logger.c",
                "loop.c",
                "node-driver.c",
                "null-audio-sink.c",
                "plugin.c",
                "system.c",
            },
        });
        _ = PipewirePlugin.build(b, pm_ctx, .{
            .name = "videoconvert",
            .files = &.{
                "plugin.c",
                "videoadapter.c",
                "videoconvert-dummy.c",
            },
        });

        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "adapter",
            .files = &.{
                "module-adapter.c",
                "module-adapter/adapter.c",
                "spa/spa-node.c",
            },
        });
        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "client-device",
            .files = &.{
                "module-client-device.c",
                "module-client-device/resource-device.c",
                "module-client-device/proxy-device.c",
                "module-client-device/protocol-native.c",
            },
        });
        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "client-node",
            .files = &.{
                "module-client-node.c",
                "module-client-node/remote-node.c",
                "module-client-node/client-node.c",
                "module-client-node/protocol-native.c",
                "spa/spa-node.c",
            },
        });
        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "metadata",
            .files = &.{
                "module-metadata.c",
                "module-metadata/proxy-metadata.c",
                "module-metadata/metadata.c",
                "module-metadata/protocol-native.c",
            },
        });
        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "protocol-native",
            .files = &.{
                "module-protocol-native.c",
                "module-protocol-native/local-socket.c",
                "module-protocol-native/portal-screencast.c",
                "module-protocol-native/protocol-native.c",
                "module-protocol-native/protocol-footer.c",
                "module-protocol-native/security-context.c",
                "module-protocol-native/connection.c",
            },
        });
        _ = PipewireModule.build(b, pm_ctx, .{
            .name = "session-manager",
            .files = &.{
                "module-session-manager.c",
                "module-session-manager/client-endpoint/client-endpoint.c",
                "module-session-manager/client-endpoint/endpoint-stream.c",
                "module-session-manager/client-endpoint/endpoint.c",
                "module-session-manager/client-session/client-session.c",
                "module-session-manager/client-session/endpoint-link.c",
                "module-session-manager/client-session/session.c",
                "module-session-manager/endpoint-link.c",
                "module-session-manager/endpoint-stream.c",
                "module-session-manager/endpoint.c",
                "module-session-manager/protocol-native.c",
                "module-session-manager/proxy-session-manager.c",
                "module-session-manager/session.c",
            },
        });
    }

    // Build the examples
    {
        const screen_play = b.addExecutable(.{
            .name = "screen_play",
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
            }),
        });
        screen_play.addCSourceFile(.{
            .file = b.path("src/screen-play.c"),
        });
        b.installArtifact(screen_play);

        screen_play.linkLibC();

        const sdl = b.dependency("sdl", .{
            .optimize = optimize,
            .target = target,
        });
        screen_play.linkLibrary(sdl.artifact("SDL3"));

        var dep: std.Build.Dependency = .{ .builder = b };
        linkAndInstall(b, &dep, screen_play);

        const run_step = b.step("screen-play", "Run the screen-play example");

        const run_cmd = b.addRunArtifact(screen_play);
        run_cmd.setCwd(.{ .cwd_relative = b.getInstallPath(.bin, "") });
        run_step.dependOn(&run_cmd.step);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }
}

/// You may call this externally to link to libpipewire and install its dependencies alongside the
/// binary. Remember that you can import build scripts by module name in your build.zig files.
pub fn linkAndInstall(
    b: *std.Build,
    dep: *std.Build.Dependency,
    exe: *std.Build.Step.Compile,
) void {
    // Statically link libpipewire
    exe.linkLibrary(dep.artifact("pipewire-0.3"));

    // Note that the cache rpath will still be present: https://github.com/ziglang/zig/issues/24349
    exe.root_module.addRPathSpecial("$ORIGIN/pipewire-0.3");

    // Install Pipewire's dependencies
    b.installDirectory(.{
        .install_dir = .bin,
        .source_dir = dep.namedWriteFiles("pipewire-0.3").getDirectory(),
        .install_subdir = "pipewire-0.3",
    });
}

const flags: []const []const u8 = &.{
    "-fvisibility=hidden",
    "-fno-strict-aliasing",
    "-Wno-missing-field-initializers",
    "-Wno-unused-parameter",
    "-Wno-pedantic",
    "-D_GNU_SOURCE",
    "-DFASTPATH",
};

pub const PluginAndModuleCtx = struct {
    upstream: *std.Build.Dependency,
    config: *std.Build.Step.ConfigHeader,
    version: *std.Build.Step.ConfigHeader,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    install_dir: *std.Build.Step.WriteFile,
    libpipewire: *std.Build.Step.Compile,
};

pub const PipewireModule = struct {
    name: []const u8,
    files: []const []const u8,

    fn build(
        b: *std.Build,
        ctx: PluginAndModuleCtx,
        self: PipewireModule,
    ) *std.Build.Step.Compile {
        const lib = b.addLibrary(.{
            .name = b.fmt("pipewire-module-{s}", .{self.name}),
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = ctx.target,
                .optimize = ctx.optimize,
            }),
        });
        lib.addCSourceFiles(.{
            .root = ctx.upstream.path("src/modules"),
            .files = self.files,
            .flags = flags,
        });
        lib.addIncludePath(ctx.upstream.path("spa/include"));
        lib.addIncludePath(ctx.upstream.path("src"));
        lib.addConfigHeader(ctx.version);
        lib.addConfigHeader(ctx.config);
        lib.linkLibC();

        return lib;
    }
};

pub const PipewirePlugin = struct {
    name: []const u8,
    files: []const []const u8,

    pub fn build(
        b: *std.Build,
        ctx: PluginAndModuleCtx,
        self: PipewirePlugin,
    ) *std.Build.Step.Compile {
        const lib = b.addLibrary(.{
            .name = b.fmt("spa-{s}", .{self.name}),
            .linkage = .static,
            .root_module = b.createModule(.{
                .target = ctx.target,
                .optimize = ctx.optimize,
            }),
        });
        lib.addCSourceFiles(.{
            .root = ctx.upstream.path(b.pathJoin(&.{
                "spa",
                "plugins",
                self.name,
            })),
            .files = self.files,
            .flags = flags,
        });
        lib.addIncludePath(ctx.upstream.path("spa/include"));
        lib.addConfigHeader(ctx.config);
        lib.linkLibC();

        return lib;
    }
};
