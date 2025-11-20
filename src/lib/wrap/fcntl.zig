//! Pipewire loads some config at runtime. This file stubs out the access to that config, thereby
//! removing the requirement to ship config files alongside your executable or have a dependence on
//! user installed config files.

const std = @import("std");
const log = std.log.scoped(.wrap_dlfcn);
const fmtFlags = @import("format.zig").fmtFlags;

/// The path pipewire looks for client config at.
const client_config_path = "pipewire-0.3/confdata/client.conf";

/// The current client config file descriptor, or -1 if not open.
var client_config_fd: c_int = -1;

/// If we're stating a config file, fake the result.
pub export fn __wrap_stat(
    noalias pathname_c: [*:0]const u8,
    noalias statbuf: *std.c.Stat,
) callconv(.c) c_int {
    const pathname = std.mem.span(pathname_c);
    const result, const strategy = b: {
        if (std.mem.endsWith(u8, pathname, ".so")) {
            statbuf.* = std.mem.zeroInit(std.c.Stat, .{ .mode = std.c.S.IFREG });
            break :b .{ 0, "faked" };
        } else {
            break :b .{ std.c.stat(pathname_c, statbuf), "real" };
        }
    };
    log.debug("stat(\"{f}\", {*}) -> {} (statbuf.* == {f}) ({s})", .{
        std.zig.fmtString(pathname),
        statbuf,
        result,
        fmtFlags(statbuf.*),
        strategy,
    });
    return result;
}

/// If we're calling access on a config file, fake the result.
pub export fn __wrap_access(path_c: [*:0]const u8, mode: c_int) callconv(.c) c_int {
    const path = std.mem.span(path_c);

    const result, const strategy = b: {
        if (mode == std.c.R_OK and
            std.mem.eql(u8, path, client_config_path))
        {
            break :b .{ 0, "faked" };
        } else {
            break :b .{ std.c.access(path, @intCast(mode)), "real" };
        }
    };
    log.debug("access(\"{f}\", {}) -> {} ({s})", .{
        std.zig.fmtString(path),
        mode,
        result,
        strategy,
    });
    return result;
}

/// If we're calling open on a config file, fake the result.
pub export fn __wrap_open(path_c: [*:0]const u8, flags: std.c.O, ...) callconv(.c) c_int {
    const path = std.mem.span(path_c);
    var args = @cVaStart();
    defer @cVaEnd(&args);

    const result, const strategy = b: {
        if (std.meta.eql(flags, .{ .CLOEXEC = true, .ACCMODE = .RDONLY }) and
            std.mem.eql(u8, path, client_config_path))
        {
            if (client_config_fd >= 0) @panic("client_config_path already open");
            client_config_fd = std.c.open("/dev/null", flags, args);
            break :b .{ client_config_fd, "faked" };
        } else {
            break :b .{ std.c.open(path_c, flags, args), "real" };
        }
    };
    log.info("open(\"{f}\", {f}, ...) -> {} ({s})", .{
        std.zig.fmtString(path),
        fmtFlags(flags),
        result,
        strategy,
    });
    return result;
}

/// If we're closing a config file, reset `client_config_fd`.
pub export fn __wrap_close(fd: c_int) callconv(.c) c_int {
    if (fd == client_config_fd) client_config_fd = -1;
    const result = std.c.close(fd);
    log.debug("close({}) -> {}", .{ fd, result });
    return result;
}
