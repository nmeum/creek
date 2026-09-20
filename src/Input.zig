const std = @import("std");
const log = std.log;

const wl = @import("wayland").client.wl;

const Bar = @import("Bar.zig");
const Input = @This();

const render = @import("render.zig");
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
    self.pointer.x = 0;
    self.pointer.y = 0;
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

fn renderTags(bar: *Bar, event: []const u8) void {
    render.renderTags(bar) catch |err| {
        log.err("renderTags failed on {s} for monitor {}: {s}", .{
            event,
            bar.monitor.globalName,
            @errorName(err),
        });
    };
    bar.tags.surface.commit();
}

fn updateTagHover(bar: *Bar, x: i32, event: []const u8) void {
    if (x < bar.tags_width) {
        if (bar.monitor.tags.handleMotion(
            x,
            @as(u32, @intCast(bar.tags_width)),
        )) {
            renderTags(bar, event);
        }
    } else if (bar.monitor.tags.clearHover()) {
        renderTags(bar, event);
    }
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
            const found_bar = state.wayland.findBar(data.surface);
            input.pointer.bar = found_bar;
            input.pointer.surface = data.surface;
            if (found_bar) |bar| {
                updateTagHover(bar, input.pointer.x, "enter");
            }
        },
        .leave => {
            if (input.pointer.bar) |bar| {
                _ = bar.monitor.tags.clearHover();
                renderTags(bar, "leave");
            }
            input.pointer.bar = null;
            input.pointer.surface = null;
        },
        .motion => |data| {
            const x = data.surface_x.toInt();
            input.pointer.x = x;
            input.pointer.y = data.surface_y.toInt();
            if (input.pointer.bar) |bar| {
                updateTagHover(bar, x, "motion");
            }
        },
        .button => |data| {
            if (data.state != .pressed) return;
            if (input.pointer.bar) |bar| {
                if (!bar.configured) return;
                const tags_surface = bar.tags.surface;
                const text_surface = bar.text.surface;
                const clicked_tags =
                    input.pointer.surface == tags_surface;
                const clicked_text =
                    input.pointer.surface == text_surface;
                if (!clicked_tags and !clicked_text) return;
                const x: i32 = input.pointer.x;
                if (clicked_text) {
                    bar.handleStatusClick(x);
                    return;
                }
                if (clicked_tags) {
                    if (x >= 0 and x < @as(i32, @intCast(bar.tags_width))) {
                        _ = bar.monitor.tags.handleClick(@intCast(x));
                    }
                }
            }
        },
        .axis => |data| {
            if (data.axis != .vertical_scroll) return;
            if (input.pointer.bar) |bar| {
                if (input.pointer.surface == bar.text.surface) {
                    const x: i32 = input.pointer.x;
                    const direction: []const u8 = if (data.value.toDouble() < 0) "up" else "down";
                    bar.handleStatusScroll(x, direction);
                    return;
                }
            }
        },
        else => {},
    }
}
