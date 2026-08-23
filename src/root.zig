const std = @import("std");
const Io = std.Io;

pub fn printMessage(writer: *Io.Writer) Io.Writer.Error!void {
    return writer.print("Hello from Logi!\n", .{});
}
