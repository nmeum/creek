const std = @import("std");
const log = std.log;
const Mutex = std.Thread.Mutex;

const wl = @import("wayland").client.wl;

const Bar = @import("Bar.zig");
const Monitor = @import("Monitor.zig");
const render = @import("render.zig");
const zriver = @import("wayland").client.zriver;
const state = &@import("root").state;

pub const Seat = @This();

seat_status: *zriver.SeatStatusV1,
current_output: ?*wl.Output,
window_title: ?[:0]u8,
status_buffer: [4096]u8 = undefined,
status_text: std.io.FixedBufferStream([]u8),
mtx: Mutex,

pub fn create() !*Seat {
    const self = try state.gpa.create(Seat);
    const manager = state.wayland.status_manager.?;
    const seat = state.wayland.seat.?;

    self.mtx = Mutex{};
    self.current_output = null;
    self.window_title = null;
    self.seat_status = try manager.getRiverSeatStatus(seat);
    self.seat_status.setListener(*Seat, seatListener, self);

    self.status_text = std.io.fixedBufferStream(&self.status_buffer);
    return self;
}

pub fn destroy(self: *Seat) void {
    self.mtx.lock();
    if (self.window_title) |w| {
        state.gpa.free(w);
    }
    self.mtx.unlock();

    self.seat_status.destroy();
    state.gpa.destroy(self);
}

pub fn focusedMonitor(self: *Seat) ?*Monitor {
    // If there is no current monitor, e.g. on startup use the first one.
    //
    // TODO: Find a better way to do this.
    if (self.current_output == null) {
        const items = state.wayland.monitors.items;
        if (items.len > 0) {
            return items[0];
        }
    }

    for (state.wayland.monitors.items) |monitor| {
        if (monitor.output == self.current_output) {
            return monitor;
        }
    }

    return null;
}

pub fn focusedBar(self: *Seat) ?*Bar {
    if (self.focusedMonitor()) |m| {
        return m.confBar();
    }

    return null;
}

fn updateTitle(self: *Seat, data: [*:0]const u8) void {
    const title = std.mem.sliceTo(data, 0);

    self.mtx.lock();
    defer self.mtx.unlock();

    if (self.window_title) |t| {
        state.gpa.free(t);
    }
    if (title.len == 0) {
        self.window_title = null;
    } else {
        const vz = state.gpa.allocSentinel(u8, title.len, 0) catch |err| {
            log.err("allocSentinel failed for window title: {s}\n", .{@errorName(err)});
            return;
        };
        @memcpy(vz[0..vz.len], title);
        self.window_title = vz;
    }
}

fn focusedOutput(self: *Seat, output: *wl.Output) void {
    var monitor: ?*Monitor = null;
    for (state.wayland.monitors.items) |m| {
        if (m.output == output) {
            monitor = m;
            break;
        }
    }

    if (monitor) |m| {
        if (m.confBar()) |bar| {
            self.current_output = m.output;
            render.renderText(bar, self.status_text.getWritten()) catch |err| {
                log.err("renderText failed on focus for monitor {}: {s}",
                    .{m.globalName, @errorName(err)});
                return;
            };

            bar.text.surface.commit();
            bar.background.surface.commit();
        }
    } else {
        log.err("seatListener: couldn't find focused output", .{});
    }
}

fn unfocusedOutput(self: *Seat, output: *wl.Output) void {
    var monitor: ?*Monitor = null;
    for (state.wayland.monitors.items) |m| {
        if (m.output == output) {
            monitor = m;
            break;
        }
    }

    if (monitor) |m| {
        if (m.confBar()) |bar| {
            render.resetText(bar) catch |err| {
                log.err("resetText failed for monitor {}: {s}",
                    .{bar.monitor.globalName, @errorName(err)});
            };
            bar.text.surface.commit();

            render.renderTitle(bar, null) catch |err| {
                log.err("renderTitle failed on unfocus for monitor {}: {s}",
                    .{bar.monitor.globalName, @errorName(err)});
                return;
            };

            bar.title.surface.commit();
            bar.background.surface.commit();
        }
    } else {
        log.err("seatListener: couldn't find unfocused output", .{});
    }

    self.current_output = null;
}

fn focusedView(self: *Seat, title: [*:0]const u8) void {
    self.updateTitle(title);
    if (self.focusedBar()) |bar| {
        render.renderTitle(bar, self.window_title) catch |err| {
            log.err("renderTitle failed on focused view for monitor {}: {s}",
                .{bar.monitor.globalName, @errorName(err)});
            return;
        };

        bar.title.surface.commit();
        bar.background.surface.commit();
    }
}

fn seatListener(
    _: *zriver.SeatStatusV1,
    event: zriver.SeatStatusV1.Event,
    seat: *Seat,
) void {
    switch (event) {
        .focused_output => |data| seat.focusedOutput(data.output.?),
        .unfocused_output => |data| seat.unfocusedOutput(data.output.?),
        .focused_view => |data| seat.focusedView(data.title),
    }
}
