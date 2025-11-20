const std = @import("std");
const build_zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    // Get the library and example build options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const host_target = b.resolveTargetQuery(.{});
    const host_optimize = .Debug;

    const rtprio_client = b.option(u8, "rtprio_client", "PipeWire clients realtime priority") orelse 83;
    if (rtprio_client < 11 or rtprio_client > 99) @panic("invalid rtprio_client");

    const rtprio_server = b.option(u8, "rtprio_server", "PipeWire server realtime priority") orelse 88;
    if (rtprio_server < 11 or rtprio_server > 99) @panic("invalid rtprio_server");

    // Get the example specific build options
    const use_zig_module = b.option(
        bool,
        "use_zig_module",
        "Link examples to Pipewire as a Zig module, if or unset links via a static library.",
    ) orelse true;

    const example_options = b.addOptions();
    example_options.addOption(bool, "use_zig_module", use_zig_module);

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

    // Create the pipewire static library
    const libpipewire = b.addLibrary(.{
        .name = "pipewire-0.3",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib/wrap/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    {
        // Add the source files
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

        // XXX: don't install this, embed it
        // Build and install the library configuration
        {
            const generate_conf = b.addExecutable(.{
                .name = "generate_conf",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/build/generate_conf.zig"),
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

        // Build the library configuration headers
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

        // Build the library plugins and modules
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

        // Include and install the library headers
        {
            libpipewire.addIncludePath(b.dependency("valgrind_h", .{}).path(""));
            libpipewire.addIncludePath(upstream.path("spa/include"));
            libpipewire.addIncludePath(upstream.path("src"));
            libpipewire.addConfigHeader(version_h);
            libpipewire.addConfigHeader(config_h);

            libpipewire.installHeadersDirectory(upstream.path("src/pipewire"), "pipewire", .{});
            libpipewire.installHeadersDirectory(upstream.path("spa/include/spa"), "spa", .{});
            libpipewire.installConfigHeader(version_h);
        }

        // Install the library
        b.installArtifact(libpipewire);
    }

    // Create the translated C module for importing pipewire headers into Zig. See the source file
    // for why we're caching this rather than using translate c.
    const c = b.createModule(.{
        .root_source_file = b.path("src/lib/c.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Create the zig module. Using this rather than the static library allows for easier
    // integration, and ties logging to the standard library logger.
    const pipewire_zig = b.addModule("pipewire", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "c", .module = c }},
    });
    pipewire_zig.linkLibrary(libpipewire);

    // Build the video play example.
    {
        const video_play = b.addExecutable(.{
            .name = "video-play",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/examples/video_play.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });

        const sdl = b.dependency("sdl", .{
            .optimize = optimize,
            .target = target,
        });

        if (use_zig_module) {
            video_play.root_module.addImport("pipewire", pipewire_zig);
        } else {
            video_play.linkLibrary(libpipewire);
            video_play.root_module.addImport("pipewire", c);
        }

        video_play.root_module.addOptions("example_options", example_options);

        video_play.linkLibrary(sdl.artifact("SDL3"));
        b.installArtifact(video_play);

        var dep: std.Build.Dependency = .{ .builder = b };
        linkAndInstall(b, &dep, video_play);

        const run_step = b.step("video-play", "Run the video-play example");

        const run_cmd = b.addRunArtifact(video_play);
        // XXX: cwd...
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

    // Install Pipewire's dependencies
    b.installDirectory(.{
        .install_dir = .bin,
        .source_dir = dep.namedWriteFiles("pipewire-0.3").getDirectory(),
        .install_subdir = "pipewire-0.3",
    });
}

/// Flags uses for all pipewire libraries.
const flags: []const []const u8 = &.{
    // Common build flags for libpipewire.
    "-fvisibility=hidden",
    "-fno-strict-aliasing",
    "-Wno-missing-field-initializers",
    "-Wno-unused-parameter",
    "-Wno-pedantic",
    "-D_GNU_SOURCE",
    "-DFASTPATH",

    // Translate C can't translate some of the variadic functions API so they get demoted to
    // externs. However, since they're present only in headers and marked as `SPA_API_IMPL` which
    // which defaults to `static inline`, the symbols end up being missing. We instead mark them as
    // weak so that we don't get duplicate symbols, but are still able to reference the C
    // implementations.
    "-DSPA_API_IMPL=__attribute__((weak))",

    // XXX: make function like to check arg counts
    // Wrap the standard library functions we want to replace with our own implementations to avoid
    // relying on a dynamic linker.
    "-Ddlopen=__wrap_dlopen",
    "-Ddlclose=__wrap_dlclose",
    "-Ddlsym=__wrap_dlsym",
    "-Ddlerror=__wrap_dlerror",
    "-Ddlinfo=__wrap_dlinfo",
    "-Dstat=__wrap_stat",
    "-Daccess=__wrap_access",
    "-Dopen=__wrap_open",
    "-Dclose=__wrap_close",

    // Since `spa_autoclose` points to a function defined in a header, its close doesn't get
    // wrapped. Wrap it manually.
    "-Dspa_autoclose=__attribute__((__cleanup__(__wrap_close)))",
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

/// A pipewire module. These are typically opened with `dlopen`, but we're going to link to them
/// statically.
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
                .link_libc = true,
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

        namespace(lib, "pipewire__module_init");
        namespace(lib, "mod_topic");

        ctx.libpipewire.addIncludePath(ctx.upstream.path("spa/include"));
        ctx.libpipewire.linkLibrary(lib);

        return lib;
    }
};

/// A pipewire plugin. These are typically opened with `dlopen`, but we're going to link to them
/// statically.
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
                .link_libc = true,
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

        namespace(lib, "spa_handle_factory_enum");
        namespace(lib, "spa_log_topic_enum");

        ctx.libpipewire.addIncludePath(ctx.upstream.path("spa/include"));
        ctx.libpipewire.linkLibrary(lib);

        return lib;
    }
};

/// Namespaces a symbol using the preprocessor.
pub fn namespace(library: *std.Build.Step.Compile, symbol: []const u8) void {
    const b = library.root_module.owner;
    library.root_module.addCMacro(
        symbol,
        b.fmt("{f}", .{Namespaced.init(library.name, symbol)}),
    );
}

/// A namespaced symbol.
pub const Namespaced = struct {
    prefix: []const u8,
    symbol: []const u8,

    pub fn init(prefix: []const u8, symbol: []const u8) Namespaced {
        return .{
            .prefix = prefix,
            .symbol = symbol,
        };
    }

    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        for (self.prefix) |c| {
            switch (c) {
                '-' => try writer.writeByte('_'),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("__");
        try writer.writeAll(self.symbol);
    }
};
