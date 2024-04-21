const std = @import("std");
const log = std.log;

const wl = @import("wayland").client.wl;

const Bar = @import("Bar.zig");
const Input = @This();

const state = &@import("root").state;

globalName: u32,

pointer: struct {
    pointer: ?*wl.Pointer,
    x: i32,
    y: i32,
    bar: ?*Bar,
    surface: ?*wl.Surface,
},

pub fn create(name: u32) !*Input {
    const self = try state.gpa.create(Input);
    const seat = state.wayland.seat.?;

    self.globalName = name;
    self.pointer.pointer = null;
    self.pointer.bar = null;
    self.pointer.surface = null;

    seat.setListener(*Input, listener, self);
    return self;
}

pub fn destroy(self: *Input) void {
    if (self.pointer.pointer) |pointer| {
        pointer.release();
    }
    state.gpa.destroy(self);
}

fn listener(seat: *wl.Seat, event: wl.Seat.Event, input: *Input) void {
    switch (event) {
        .capabilities => |data| {
            if (input.pointer.pointer) |pointer| {
                pointer.release();
                input.pointer.pointer = null;
            }
            if (data.capabilities.pointer) {
                input.pointer.pointer = seat.getPointer() catch |err| {
                    log.err("cannot obtain seat pointer: {s}", .{@errorName(err)});
                    return;
                };
                input.pointer.pointer.?.setListener(
                    *Input,
                    pointerListener,
                    input,
                );
            }
        },
        .name => {},
    }
}

fn pointerListener(
    _: *wl.Pointer,
    event: wl.Pointer.Event,
    input: *Input,
) void {
    switch (event) {
        .enter => |data| {
            input.pointer.x = data.surface_x.toInt();
            input.pointer.y = data.surface_y.toInt();
            const bar = state.wayland.findBar(data.surface);
            input.pointer.bar = bar;
            input.pointer.surface = data.surface;
        },
        .leave => |_| {
            input.pointer.bar = null;
            input.pointer.surface = null;
        },
        .motion => |data| {
            input.pointer.x = data.surface_x.toInt();
            input.pointer.y = data.surface_y.toInt();
        },
        .button => |data| {
            if (data.state != .pressed) return;
            if (input.pointer.bar) |bar| {
                if (!bar.configured) return;

                const tagsSurface = bar.tags.surface;
                if (input.pointer.surface != tagsSurface) return;

                const x: u32 = @intCast(input.pointer.x);
                if (x < bar.height * @as(u16, bar.monitor.tags.tags.len)) {
                    bar.monitor.tags.handleClick(x) catch |err| {
                        log.err("handleClick failed for monitor {}: {s}",
                                .{bar.monitor.globalName, @errorName(err)});
                        return;
                    };
                }
            }
        },
        else => {},
    }
}
