const std = @import("std");
const posix = std.posix;
const platform = @import("root.zig");
const Io = std.Io;

var g_io: ?Io = null;

fn handleSigInt(sig: c_int) callconv(.c) void {
    _ = sig;
    if (g_io) |io| {
        platform.triggerCancel(io);
    }
}

pub fn impl(init: std.process.Init) !void {
    g_io = init.io;

    var act = posix.Sigaction{
        .handler = .{ .handler = @ptrCast(&handleSigInt) },
        .mask = std.mem.zeroes(posix.sigset_t),
        .flags = 0,
    };

    posix.sigaction(posix.SIG.INT, &act, null);
    posix.sigaction(posix.SIG.TERM, &act, null);

    try platform.run(init.io, init.gpa);
}
