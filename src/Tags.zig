const std = @import("std");

const zriver = @import("wayland").client.zriver;

const Monitor = @import("wayland.zig").Monitor;
const render = @import("render.zig");
const Input = @import("wayland.zig").Input;
const State = @import("main.zig").State;
const Tags = @This();

monitor: *Monitor,
outputStatus: *zriver.OutputStatusV1,
tags: [9]Tag,

pub const Tag = struct {
    label: u8,
    focused: bool = false,
    occupied: bool = false,
};

pub fn create(state: *State, monitor: *Monitor) !*Tags {
    const self = try state.gpa.create(Tags);
    const globals = &state.wayland.globals;

    self.monitor = monitor;
    self.outputStatus = try globals.statusManager.getRiverOutputStatus(
        monitor.output,
    );
    for (self.tags) |*tag, i| {
        tag.label = '1' + @intCast(u8, i);
    }

    self.outputStatus.setListener(*Tags, outputStatusListener, self);
    return self;
}

pub fn destroy(self: *Tags) void {
    self.outputStatus.destroy();
    self.monitor.state.gpa.destroy(self);
}

fn outputStatusListener(
    _: *zriver.OutputStatusV1,
    event: zriver.OutputStatusV1.Event,
    tags: *Tags,
) void {
    switch (event) {
        .focused_tags => |data| {
            for (tags.tags) |*tag, i| {
                const mask = @as(u32, 1) << @intCast(u5, i);
                tag.focused = data.tags & mask != 0;
            }
        },
        .view_tags => |data| {
            for (tags.tags) |*tag| {
                tag.occupied = false;
            }
            for (data.tags.slice(u32)) |view| {
                for (tags.tags) |*tag, i| {
                    const mask = @as(u32, 1) << @intCast(u5, i);
                    if (view & mask != 0) tag.occupied = true;
                }
            }
        },
    }
    if (tags.monitor.bar) |bar| {
        if (bar.configured) {
            render.renderTags(bar) catch return;
            bar.tags.surface.commit();
            bar.background.surface.commit();
        }
    }
}

pub fn handleClick(self: *Tags, x: u32, input: *Input) !void {
    const state = self.monitor.state;
    const control = state.wayland.globals.control;

    if (self.monitor.bar) |bar| {
        const index = x / bar.height;
        const payload = try std.fmt.allocPrintZ(
            state.gpa,
            "{d}",
            .{@as(u32, 1) << @intCast(u5, index)},
        );
        defer state.gpa.free(payload);

        control.addArgument("set-focused-tags");
        control.addArgument(payload);
        const callback = try control.runCommand(input.seat);
        _ = callback;
    }
}
