const std = @import("std");
const Io = std.Io;

const logi = @import("logi");

pub fn main(init: std.process.Init) !void {
    try logi.start(init.io, init.gpa);
}
