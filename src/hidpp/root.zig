const std = @import("std");
const mem = std.mem;
const Io = std.Io;
const builtin = @import("builtin");
const linux_impl = @import("linux.zig");
const windows_impl = @import("windows.zig");
const HidDeviceInfo = @import("../hidapi/root.zig").HidDeviceInfo;

pub const HidMessageHeader = extern struct {
    report_id: u8,
    device_index: u8,
    feature_index: u8,
    function_and_software_id: u8,

    pub fn init(report_id: u8) @This() {
        return .{
            .report_id = report_id,
            .device_index = 0,
            .feature_index = 0,
            .function_and_software_id = 0,
        };
    }
};

pub const HidShortMessage = extern struct {
    header: HidMessageHeader,
    params: [3]u8,

    pub const init: @This() = .{
        .header = .init(0x10),
        .params = mem.zeroes([3]u8),
    };

    pub fn toBytes(self: @This()) [@sizeOf(@This())]u8 {
        return mem.toBytes(self);
    }
};

pub const HidLongMessage = extern struct {
    header: HidMessageHeader,
    params: [16]u8,

    pub const init: @This() = .{
        .header = .init(0x11),
        .params = mem.zeroes([16]u8),
    };

    pub fn toBytes(self: @This()) [@sizeOf(@This())]u8 {
        return mem.toBytes(self);
    }
};

pub const RawMessage = struct {
    const max_bytes_len = 32;

    bytes: [max_bytes_len]u8,
    len: usize,

    pub fn asSlice(self: *const @This()) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const HidMessage = union(enum) {
    short: HidShortMessage,
    long: HidLongMessage,
    raw: RawMessage,

    pub fn init(bytes: []const u8) !@This() {
        if (bytes.len == 0)
            return error.EmptyBytesSlice;

        return switch (bytes[0]) {
            0x10, 0x02 => .{ .short = mem.bytesToValue(HidShortMessage, bytes) },
            0x11, 0x03 => .{ .long = mem.bytesToValue(HidLongMessage, bytes) },
            else => {
                var msg: RawMessage = .{ .bytes = undefined, .len = @min(RawMessage.max_bytes_len, bytes.len) };
                @memcpy(msg.bytes[0..msg.len], bytes[0..msg.len]);
                return .{ .raw = msg };
            },
        };
    }
};

const Read = switch (builtin.os.tag) {
    .windows => @TypeOf(windows_impl.read),
    .linux => @TypeOf(linux_impl.read),
    else => @compileError("Unsupported platform"),
};

const Write = switch (builtin.os.tag) {
    .windows => @TypeOf(windows_impl.write),
    .linux => @TypeOf(linux_impl.write),
    else => @compileError("Unsupported platform"),
};

pub const HidDevice = struct {
    file: Io.File,
    info: HidDeviceInfo,

    pub fn init(io: Io, info: HidDeviceInfo) !@This() {
        return .{
            .file = try Io.Dir.cwd().openFile(
                io,
                info.getPath(),
                .{ .mode = .read_write },
            ),
            .info = info,
        };
    }

    pub fn cancel(self: *@This()) void {
        switch (builtin.os.tag) {
            .windows => {
                const win = std.os.windows;
                const CancelIoEx = struct {
                    extern "kernel32" fn CancelIoEx(hFile: win.HANDLE, lpOverlapped: ?*anyopaque) callconv(.winapi) win.BOOL;
                }.CancelIoEx;
                _ = CancelIoEx(self.file.handle, null);
            },
            .linux => {
                // Not supported, file reads might block until unblocked or closed
            },
            else => unreachable,
        }
    }

    pub fn deinit(self: *@This(), io: Io) void {
        self.file.close(io);
        self.* = undefined;
    }

    pub fn read(self: *@This(), buf: []u8) !HidMessage {
        if (buf.len == 0) return error.EmptyBuffer;

        return switch (builtin.os.tag) {
            .windows => windows_impl.read(self.file.handle, buf),
            .linux => linux_impl.read(self.file.handle, buf),
            else => unreachable,
        };
    }

    pub fn write(self: *@This(), msg: HidMessage) !void {
        const bytes: []const u8 = switch (msg) {
            .short => |s| &s.toBytes(),
            .long => |l| &l.toBytes(),
            .raw => |r| r.asSlice(),
        };

        const written = switch (builtin.os.tag) {
            .windows => try windows_impl.write(self.file.handle, bytes),
            .linux => try linux_impl.write(self.file.handle, bytes),
            else => unreachable,
        };

        std.debug.assert(bytes.len == written);
    }
};

test "HidMessageHeader.init returns a valid initialized header" {
    const header: HidMessageHeader = .init(0x11);
    try std.testing.expectEqual(0x11, header.report_id);
    try std.testing.expectEqual(0, header.device_index);
    try std.testing.expectEqual(0, header.feature_index);
    try std.testing.expectEqual(0, header.function_and_software_id);
}

test "HidShortMessage.init returns a valid initialized message" {
    const msg: HidShortMessage = .init;
    try std.testing.expectEqual(0x10, msg.header.report_id);
    try std.testing.expectEqual(0, msg.header.device_index);
    try std.testing.expectEqual(0, msg.header.feature_index);
    try std.testing.expectEqual(0, msg.header.function_and_software_id);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, &msg.params);
}

test "HidLongMessage.init returns a valid initialized message" {
    const msg: HidLongMessage = .init;
    try std.testing.expectEqual(0x11, msg.header.report_id);
    try std.testing.expectEqual(0, msg.header.device_index);
    try std.testing.expectEqual(0, msg.header.feature_index);
    try std.testing.expectEqual(0, msg.header.function_and_software_id);
    const expected: [16]u8 = std.simd.repeat(16, [_]u8{0});
    try std.testing.expectEqualSlices(u8, &expected, &msg.params);
}

test "HidMessage.init returns error on empty slice" {
    try std.testing.expectError(error.EmptyBytesSlice, HidMessage.init(&.{}));
}

test "HidMessage.init parses short message" {
    var bytes: [@sizeOf(HidShortMessage)]u8 = std.mem.zeroes([@sizeOf(HidShortMessage)]u8);
    bytes[0] = 0x10;
    bytes[1] = 0x01; // device index

    const msg = try HidMessage.init(&bytes);
    try std.testing.expectEqual(.short, std.meta.activeTag(msg));
    try std.testing.expectEqual(0x10, msg.short.header.report_id);
    try std.testing.expectEqual(0x01, msg.short.header.device_index);
}

test "HidMessage.init parses long message" {
    var bytes: [@sizeOf(HidLongMessage)]u8 = std.mem.zeroes([@sizeOf(HidLongMessage)]u8);
    bytes[0] = 0x11;
    bytes[1] = 0x02; // device index

    const msg = try HidMessage.init(&bytes);
    try std.testing.expectEqual(.long, std.meta.activeTag(msg));
    try std.testing.expectEqual(0x11, msg.long.header.report_id);
    try std.testing.expectEqual(0x02, msg.long.header.device_index);
}

test "HidMessage.init parses raw message" {
    const bytes = [_]u8{ 0x05, 0x01, 0x02, 0x03 };
    const msg = try HidMessage.init(&bytes);
    try std.testing.expectEqual(.raw, std.meta.activeTag(msg));
    try std.testing.expectEqual(4, msg.raw.len);
    try std.testing.expectEqualSlices(u8, &bytes, msg.raw.asSlice());
}

fn createTestDevice(io: Io, path: []const u8) !HidDevice {
    const info = try HidDeviceInfo.init(path, 0, 0);
    return HidDevice.init(io, info);
}

test "HidDevice reads from a file" {
    const test_file_path = "r_temp";
    var short: HidShortMessage = .init;
    short.params[0] = 1;
    short.params[1] = 2;
    short.params[2] = 3;
    var test_file = try Io.Dir.cwd().createFile(std.testing.io, test_file_path, .{ .read = true });
    defer Io.Dir.cwd().deleteFile(std.testing.io, test_file_path) catch {};

    var buf: [64]u8 = undefined;
    var writer = test_file.writer(std.testing.io, &buf);
    try writer.interface.writeAll(&short.toBytes());
    try writer.flush();
    test_file.close(std.testing.io);

    var msg_buf: [@sizeOf(HidLongMessage)]u8 = undefined;
    var hid: HidDevice = try createTestDevice(std.testing.io, test_file_path);
    defer hid.deinit(std.testing.io);

    const msg = try hid.read(&msg_buf);
    try std.testing.expectEqualSlices(u8, &short.toBytes(), &msg.short.toBytes());
}

test "HidDevice writes to a file" {
    const test_file_path = "w_temp";
    var long: HidLongMessage = .init;
    long.params[0] = 1;
    long.params[1] = 2;
    long.params[2] = 3;
    const test_msg: HidMessage = .{ .long = long };
    var test_file = try Io.Dir.cwd().createFile(std.testing.io, test_file_path, .{ .read = true });
    defer {
        test_file.close(std.testing.io);
        Io.Dir.cwd().deleteFile(std.testing.io, test_file_path) catch {};
    }

    var hid: HidDevice = try createTestDevice(std.testing.io, test_file_path);
    defer hid.deinit(std.testing.io);

    try hid.write(test_msg);

    var buf: [64]u8 = undefined;
    var r_buf: [@sizeOf(HidLongMessage)]u8 = undefined;
    var file_reader = test_file.reader(std.testing.io, &buf);
    const bytes_read = try file_reader.interface.readSliceShort(&r_buf);
    try std.testing.expectEqual(@sizeOf(HidLongMessage), bytes_read);
    try std.testing.expectEqualSlices(u8, &long.toBytes(), r_buf[0..bytes_read]);
}

test "HidDevice.cancel doesn't crash" {
    const test_file_path = "c_temp";
    var test_file = try Io.Dir.cwd().createFile(std.testing.io, test_file_path, .{ .read = true });
    defer {
        test_file.close(std.testing.io);
        Io.Dir.cwd().deleteFile(std.testing.io, test_file_path) catch {};
    }

    var hid: HidDevice = try createTestDevice(std.testing.io, test_file_path);
    defer hid.deinit(std.testing.io);

    // Call cancel just to ensure it doesn't crash or behave improperly on the handle
    hid.cancel();
}
