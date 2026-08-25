const std = @import("std");
const mem = std.mem;
const Io = std.Io;

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

pub const message_buffer_size: usize = @sizeOf(HidLongMessage);

pub const HidShortMessage = extern struct {
    header: HidMessageHeader,
    params: [3]u8,

    pub const init: @This() = .{
        .header = .init(0x10),
        .params = mem.zeroes([3]u8),
    };
};

pub const HidLongMessage = extern struct {
    header: HidMessageHeader,
    params: [16]u8,

    pub const init: @This() = .{
        .header = .init(0x11),
        .params = mem.zeroes([16]u8),
    };
};

pub const HidMessage = union(enum) {
    short: *const HidShortMessage,
    long: *const HidLongMessage,

    pub fn init(bytes: []const u8) !@This() {
        if (bytes.len == 0)
            return error.EmptyBytesSlice;

        return switch (bytes[0]) {
            0x10, 0x02 => .{ .short = mem.bytesAsValue(HidShortMessage, bytes) },
            0x11, 0x03 => .{ .long = mem.bytesAsValue(HidLongMessage, bytes) },
            else => error.UnknownReportId,
        };
    }

    pub fn asBytes(self: @This()) []const u8 {
        return switch (self) {
            .short => |s| mem.asBytes(s),
            .long => |l| mem.asBytes(l),
        };
    }
};

pub const HidDevice = struct {
    file: Io.File,

    pub fn init(io: Io, path: []const u8) !@This() {
        return .{
            .file = try Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write }),
        };
    }

    pub fn deinit(self: *@This(), io: Io) void {
        self.file.close(io);
        self.* = undefined;
    }

    pub fn read(self: *@This(), buf: []u8) !HidMessage {
        const bytes_read = std.os.linux.read(self.file.handle, @ptrCast(buf), buf.len);
        return .init(buf[0..bytes_read]);
    }

    pub fn write(self: *@This(), msg: HidMessage) !void {
        const bytes = msg.asBytes();
        const written = std.os.linux.write(self.file.handle, @ptrCast(bytes), bytes.len);
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

test "HidDevice reads from a file" {
    const test_file_path = "r_temp";
    var short: HidShortMessage = .init;
    short.params[0] = 1;
    short.params[1] = 2;
    short.params[2] = 3;
    const test_msg: HidMessage = .{ .short = &short };
    var test_file = try Io.Dir.cwd().createFile(std.testing.io, test_file_path, .{ .read = true });
    defer Io.Dir.cwd().deleteFile(std.testing.io, test_file_path) catch {};

    var buf: [64]u8 = undefined;
    var writer = test_file.writer(std.testing.io, &buf);
    try writer.interface.writeAll(test_msg.asBytes());
    try writer.flush();
    test_file.close(std.testing.io);

    var msg_buf: [message_buffer_size]u8 = undefined;
    var hid: HidDevice = try .init(std.testing.io, test_file_path);
    defer hid.deinit(std.testing.io);

    const msg = try hid.read(&msg_buf);
    try std.testing.expectEqualSlices(u8, test_msg.asBytes(), msg.asBytes());
}

test "HidDevice writes to a file" {
    const test_file_path = "w_temp";
    var long: HidLongMessage = .init;
    long.params[0] = 1;
    long.params[1] = 2;
    long.params[2] = 3;
    const test_msg: HidMessage = .{ .long = &long };
    var test_file = try Io.Dir.cwd().createFile(std.testing.io, test_file_path, .{ .read = true });
    defer {
        test_file.close(std.testing.io);
        Io.Dir.cwd().deleteFile(std.testing.io, test_file_path) catch {};
    }

    var hid: HidDevice = try .init(std.testing.io, test_file_path);
    defer hid.deinit(std.testing.io);

    try hid.write(test_msg);

    var buf: [64]u8 = undefined;
    var r_buf: [message_buffer_size]u8 = undefined;
    var file_reader = test_file.reader(std.testing.io, &buf);
    const bytes_read = try file_reader.interface.readSliceShort(&r_buf);
    try std.testing.expectEqual(@sizeOf(HidLongMessage), bytes_read);
    try std.testing.expectEqualSlices(u8, test_msg.asBytes(), r_buf[0..bytes_read]);
}
