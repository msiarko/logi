const std = @import("std");
const win = std.os.windows;
const Handle = std.Io.File.Handle;
const HidMessage = @import("root.zig").HidMessage;

const OVERLAPPED = extern struct {
    Internal: win.ULONG_PTR,
    InternalHigh: win.ULONG_PTR,
    Offset: win.DWORD,
    OffsetHigh: win.DWORD,
    hEvent: win.HANDLE,
};

extern "kernel32" fn ReadFile(
    hFile: win.HANDLE,
    lpBuffer: [*:0]u8,
    nNumberOfBytesToRead: win.DWORD,
    lpNumberOfBytesRead: *win.DWORD,
    lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) win.BOOL;

extern "kernel32" fn WriteFile(
    hFile: win.HANDLE,
    lpBuffer: [*:0]const u8,
    nNumberOfBytesToWrite: win.DWORD,
    lpNumberOfBytesWritten: *win.DWORD,
    lpOverlapped: ?*OVERLAPPED,
) callconv(.winapi) win.BOOL;

pub fn read(handle: win.HANDLE, buf: []u8) !HidMessage {
    var bytes_read: win.DWORD = 0;
    const result = ReadFile(
        handle,
        @ptrCast(buf),
        @intCast(buf.len),
        &bytes_read,
        null,
    );

    if (!result.toBool()) {
        return error.ReadFileFailed;
    }

    return .init(buf[0..@intCast(bytes_read)]);
}

pub fn write(handle: win.HANDLE, bytes: []const u8) !usize {
    var bytes_written: win.DWORD = 0;
    const result = WriteFile(
        handle,
        @ptrCast(bytes),
        @intCast(bytes.len),
        &bytes_written,
        null,
    );

    if (!result.toBool()) {
        return error.WriteFileFailed;
    }

    return @intCast(bytes_written);
}
