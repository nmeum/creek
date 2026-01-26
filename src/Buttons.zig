const std = @import("std");
const log = std.log;

const zriver = @import("wayland").client.zriver;
const pixman = @import("pixman");

const Monitor = @import("Monitor.zig");
const render = @import("render.zig");
const Input = @import("Input.zig");
const Buttons = @This();

const state = &@import("root").state;

const BUTTON_COUNT = 1;
const labels: [BUTTON_COUNT]u16 = .{'R'};
const commands: [BUTTON_COUNT][3][]const u8 = .{
    .{"/bin/sh", "-c", "$(tofi-drun)"},
};
buttons: [BUTTON_COUNT]Button,
monitor: *Monitor,
output_status: *zriver.OutputStatusV1,

pub const Button = struct {
    label: u16,
    cmd: []const []const u8,
    pub fn bgColor(_: *const Button) *pixman.Color {
        return &state.config.normalBgColor;
    }

    pub fn fgColor(_: *const Button) *pixman.Color {
        return &state.config.normalFgColor;
    }

};

pub fn create(monitor: *Monitor) !*Buttons {
    const self = try state.gpa.create(Buttons);
    const manager = state.wayland.status_manager.?;

    self.monitor = monitor;
    self.output_status = try manager.getRiverOutputStatus(monitor.output);
    for (&self.buttons, 0..) |*btn, i| {
        btn.label = labels[i];
        btn.cmd = &commands[i];
    }

    self.output_status.setListener(*Buttons, outputStatusListener, self);
    return self;
}

pub fn destroy(self: *Buttons) void {
    self.output_status.destroy();
    state.gpa.destroy(self);
}

fn outputStatusListener(
    _: *zriver.OutputStatusV1,
    _: zriver.OutputStatusV1.Event,
    buttons: *Buttons,
) void {
    if (buttons.monitor.confBar()) |bar| {
        render.renderButtons(bar) catch |err| {
            log.err("renderButtons failed for monitor {}: {s}", .{ buttons.monitor.globalName, @errorName(err) });
            return;
        };

        bar.buttons.surface.commit();
        bar.background.surface.commit();
    }
}

pub fn handleClick(self: *Buttons, x: u32) !void {
    if (self.monitor.bar) |bar| {
        const index = (x / bar.height);
        _ = try std.process.Child.run(.{
            .argv = self.buttons[index].cmd,
            .allocator = state.gpa,
        });
    }
}
