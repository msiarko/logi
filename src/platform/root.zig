const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const hidpp = @import("../hidpp/root.zig");
const hidapi = @import("../hidapi/root.zig");
const HidDevice = hidpp.HidDevice;
const HidDeviceInfo = hidapi.HidDeviceInfo;

const Global = struct {
    active_devices: [8]HidDevice = undefined,
    active_devices_count: usize = 0,
    cancel_event: Io.Event = .unset,

    pub const init: @This() = .{};

    pub fn anyActiveDevices(self: *const @This()) bool {
        return self.active_devices_count > 0;
    }

    pub fn maxActiveDevicesReached(self: *const @This()) bool {
        return self.active_devices_count >= self.active_devices.len;
    }

    pub fn initDevice(self: *@This(), io: Io, info: HidDeviceInfo) !*HidDevice {
        const hd = &self.active_devices[self.active_devices_count];
        hd.* = try HidDevice.init(io, info);
        self.active_devices_count += 1;
        return hd;
    }

    pub fn deinitDevices(self: *@This(), io: Io) void {
        for (self.active_devices[0..self.active_devices_count]) |*hd| {
            hd.cancel();
            hd.deinit(io);
        }
    }
};

const Main = switch (builtin.os.tag) {
    .windows => @import("windows.zig"),
    .linux => @import("linux.zig"),
    else => @compileError("Unsupported OS"),
};

var global: Global = .init;
pub const main = Main.impl;

pub fn triggerCancel(io: Io) void {
    global.cancel_event.set(io);
}

pub fn run(io: Io, allocator: std.mem.Allocator) !void {
    var stdout = Io.File.stdout();
    var buf: [256]u8 = undefined;
    var stdout_writer = stdout.writer(io, &buf);
    var writer = &stdout_writer.interface;
    defer writer.flush() catch {};

    var devices_info = try hidapi.scanDevices(io);
    defer devices_info.deinit(io);

    var mutex: Io.Mutex = .init;
    var tasks: Io.Group = .init;
    defer tasks.cancel(io);

    while (try devices_info.next(io, allocator)) |device_info| {
        if (device_info.vendor == 0x046d) {
            if (global.maxActiveDevicesReached()) continue;

            const hd = global.initDevice(io, device_info) catch continue;
            tasks.async(io, read, .{
                io,
                &mutex,
                writer,
                hd,
            });
        }
    }

    if (!global.anyActiveDevices()) return;

    try global.cancel_event.wait(io);
    global.deinitDevices(io);
}

fn read(
    io: Io,
    mutex: *Io.Mutex,
    writer: *Io.Writer,
    hd: *HidDevice,
) Io.Cancelable!void {
    var read_buf: [32]u8 = undefined;
    while (true) {
        try io.checkCancel();
        const msg = hd.read(&read_buf) catch return Io.Cancelable.Canceled;
        const bytes: []const u8 = switch (msg) {
            .short => |s| &s.toBytes(),
            .long => |l| &l.toBytes(),
            .raw => |r| r.asSlice(),
        };

        try mutex.lock(io);
        defer mutex.unlock(io);

        writer.print("Path: {s}; Message: 0x{X}\n", .{ hd.info.path.asSlice(), bytes }) catch return Io.Cancelable.Canceled;
        writer.flush() catch return Io.Cancelable.Canceled;
    }
}

test {
    _ = std.testing.refAllDecls(hidapi);
    _ = std.testing.refAllDecls(hidpp);
}
