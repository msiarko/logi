const std = @import("std");
const linux = std.os.linux;
const HidMessage = @import("root.zig").HidMessage;

pub fn read(handle: linux.fd_t, buf: []u8) !HidMessage {
    const bytes_read = std.os.linux.read(handle, @ptrCast(buf), buf.len);
    if (bytes_read < 0) return error.ReadFailed;
    return .init(buf[0..bytes_read]);
}

pub fn write(handle: linux.fd_t, bytes: []const u8) !usize {
    const written = std.os.linux.write(handle, @ptrCast(bytes), bytes.len);
    if (written < 0) return error.WriteFailed;
    return written;
}
