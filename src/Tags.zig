const std = @import("std");
const log = std.log;

const zriver = @import("wayland").client.zriver;
const pixman = @import("pixman");

const Monitor = @import("Monitor.zig");
const render = @import("render.zig");
const Input = @import("Input.zig");
const Tags = @This();

const state = &@import("root").state;

monitor: *Monitor,
output_status: *zriver.OutputStatusV1,
tags: [9]Tag,

pub const Tag = struct {
    label: u8,
    focused: bool = false,
    occupied: bool = false,
    urgent: bool = false,

    pub fn bgColor(self: *const Tag) *pixman.Color {
        if (self.focused) {
            return &state.config.focusBgColor;
        } else if (self.urgent) {
            return &state.config.normalFgColor;
        } else {
            return &state.config.normalBgColor;
        }
    }

    pub fn fgColor(self: *const Tag) *pixman.Color {
        if (self.focused) {
            return &state.config.focusFgColor;
        } else if (self.urgent) {
            return &state.config.normalBgColor;
        } else {
            return &state.config.normalFgColor;
        }
    }
};

pub fn create(monitor: *Monitor) !*Tags {
    const self = try state.gpa.create(Tags);
    const manager = state.wayland.status_manager.?;

    self.monitor = monitor;
    self.output_status = try manager.getRiverOutputStatus(monitor.output);
    for (&self.tags, 0..) |*tag, i| {
        tag.label = '1' + @as(u8, @intCast(i));
    }

    self.output_status.setListener(*Tags, outputStatusListener, self);
    return self;
}

pub fn destroy(self: *Tags) void {
    self.output_status.destroy();
    state.gpa.destroy(self);
}

fn outputStatusListener(
    _: *zriver.OutputStatusV1,
    event: zriver.OutputStatusV1.Event,
    tags: *Tags,
) void {
    switch (event) {
        .focused_tags => |data| {
            for (&tags.tags, 0..) |*tag, i| {
                const mask = @as(u32, 1) << @as(u5, @intCast(i));
                tag.focused = data.tags & mask != 0;
            }
        },
        .urgent_tags => |data| {
            for (&tags.tags, 0..) |*tag, i| {
                const mask = @as(u32, 1) << @as(u5, @intCast(i));
                tag.urgent = data.tags & mask != 0;
            }
        },
        .view_tags => |data| {
            for (&tags.tags) |*tag| {
                tag.occupied = false;
            }
            for (data.tags.slice(u32)) |view| {
                for (&tags.tags, 0..) |*tag, i| {
                    const mask = @as(u32, 1) << @as(u5, @intCast(i));
                    if (view & mask != 0) tag.occupied = true;
                }
            }
        },
    }
    if (tags.monitor.confBar()) |bar| {
        render.renderTags(bar) catch |err| {
            log.err("renderTags failed for monitor {}: {s}", .{ tags.monitor.globalName, @errorName(err) });
            return;
        };

        bar.tags.surface.commit();
        bar.background.surface.commit();
    }
}

pub fn handleClick(self: *Tags, x: u32) !void {
    const control = state.wayland.control.?;

    if (self.monitor.bar) |bar| {
        const index = x / bar.height;
        const payload = try std.fmt.allocPrintSentinel(
            state.gpa,
            "{d}",
            .{@as(u32, 1) << @as(u5, @intCast(index))},
            0,
        );
        defer state.gpa.free(payload);

        control.addArgument("set-focused-tags");
        control.addArgument(payload);
        const callback = try control.runCommand(state.wayland.seat.?);
        _ = callback;
    }
}
