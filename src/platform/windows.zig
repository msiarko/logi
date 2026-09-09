const std = @import("std");
const windows = std.os.windows;
const platform = @import("root.zig");
const Io = std.Io;

var g_io: ?Io = null;

extern "kernel32" fn SetConsoleCtrlHandler(
    HandlerRoutine: ?*const fn (windows.DWORD) callconv(.winapi) windows.BOOL,
    Add: windows.BOOL,
) callconv(.winapi) windows.BOOL;

fn cancel(ctrl_type: windows.DWORD) callconv(.winapi) windows.BOOL {
    switch (ctrl_type) {
        0, 1, 2 => { // CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT
            if (g_io) |io| {
                platform.triggerCancel(io);
            }
            return windows.BOOL.TRUE;
        },
        else => return windows.BOOL.FALSE,
    }
}

pub fn impl(init: std.process.Init) !void {
    g_io = init.io;
    if (SetConsoleCtrlHandler(cancel, windows.BOOL.TRUE) == windows.BOOL.FALSE) {
        return error.FailedToSetConsoleHandler;
    }

    try platform.run(init.io, init.gpa);
}
