const std = @import("std");
const Io = std.Io;

const logi = @import("logi");

pub fn main(init: std.process.Init) !void {
    var buf: [128]u8 = undefined;
    const stdout = Io.File.stdout();
    var file_writer = stdout.writer(init.io, &buf);
    try logi.printMessage(&file_writer.interface);
    try file_writer.flush();
}
