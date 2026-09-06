const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const logi = @import("logi");

pub fn main(init: std.process.Init) !void {
    var stdout = Io.File.stdout();
    var buf: [1024]u8 = undefined;
    var stdout_writer = stdout.writer(init.io, &buf);
    var writer = &stdout_writer.interface;
    defer writer.flush() catch {};

    var devices = try logi.scanDevices(init.io);
    defer devices.deinit(init.io);

    var mutex: Io.Mutex = .init;
    var group: Io.Group = .init;
    defer group.cancel(init.io);

    while (try devices.next(init.io, init.gpa)) |device| {
        var mut = device;
        defer mut.deinit(init.gpa);

        if (mut.vendor == 0x046d) {
            group.async(
                init.io,
                read,
                .{
                    init.io,
                    init.gpa,
                    &mutex,
                    try init.gpa.dupe(u8, device.path),
                    writer,
                },
            );
        }
    }

    try group.await(init.io);
}

fn read(
    io: Io,
    allocator: Allocator,
    mutex: *Io.Mutex,
    path: []const u8,
    writer: *Io.Writer,
) Io.Cancelable!void {
    defer allocator.free(path);

    var read_buf: [20]u8 = undefined;
    var hd = logi.hidpp.HidDevice.init(io, path) catch |err| {
        try mutex.lock(io);
        defer mutex.unlock(io);

        writer.print("Path: {s}; Error: {s}\n", .{ path, @errorName(err) }) catch return Io.Cancelable.Canceled;
        writer.flush() catch return Io.Cancelable.Canceled;
        return Io.Cancelable.Canceled;
    };
    defer hd.deinit(io);

    while (true) {
        const msg = hd.read(&read_buf) catch return Io.Cancelable.Canceled;
        const bytes: []const u8 = switch (msg) {
            .short => |s| &s.toBytes(),
            .long => |l| &l.toBytes(),
        };

        try mutex.lock(io);
        defer mutex.unlock(io);

        writer.print("Path: {s}; Message: 0x{X}\n", .{ path, bytes }) catch return Io.Cancelable.Canceled;
        writer.flush() catch return Io.Cancelable.Canceled;
    }
}
