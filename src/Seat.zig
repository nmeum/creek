const std = @import("std");
const log = std.log;
const Mutex = std.Thread.Mutex;

const wl = @import("wayland").client.wl;

const Monitor = @import("Monitor.zig").Monitor;
const render = @import("render.zig");
const zriver = @import("wayland").client.zriver;
const state = &@import("root").state;

pub const Seat = @This();

seat_status: *zriver.SeatStatusV1,
current_output: ?*wl.Output,
window_title: ?[:0]u8,
mtx: Mutex,

pub fn create() !*Seat {
    const self = try state.gpa.create(Seat);
    const manager = state.wayland.status_manager.?;
    const seat = state.wayland.seat_wl.?;

    self.mtx = Mutex{};
    self.current_output = null;
    self.window_title = null;
    self.seat_status = try manager.getRiverSeatStatus(seat);
    self.seat_status.setListener(*Seat, seatListener, self);

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
    for (state.wayland.monitors.items) |monitor| {
        if (monitor.output == self.current_output) {
            return monitor;
        }
    }

    return null;
}

fn updateTitle(self: *Seat, data: [*:0]const u8) void {
    var title = std.mem.sliceTo(data, 0);

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
        std.mem.copy(u8, vz, title);
        self.window_title = vz;
    }
}

fn seatListener(
    _: *zriver.SeatStatusV1,
    event: zriver.SeatStatusV1.Event,
    seat: *Seat,
) void {
    switch (event) {
        .focused_output => |data| {
            for (state.wayland.monitors.items) |monitor| {
                if (monitor.output == data.output) {
                    seat.current_output = monitor.output;
                    return;
                }
            }

            log.err("seatListener: couldn't find focused output", .{});
        },
        .unfocused_output => |data| {
            var monitor: ?*Monitor = null;
            for (state.wayland.monitors.items) |m| {
                if (m.output == data.output) {
                    monitor = m;
                    break;
                }
            }

            if (monitor) |m| {
                // TODO: add getBar or something
                if (m.bar) |bar| {
                    if (bar.configured) {
                        render.renderTitle(bar, null) catch |err| {
                            log.err("renderTitle failed for monitor {}: {s}",
                                .{bar.monitor.globalName, @errorName(err)});
                            return;
                        };

                        bar.title.surface.commit();
                        bar.background.surface.commit();
                    }
                }
            } else {
                log.err("seatListener: couldn't find unfocused output", .{});
            }

            seat.current_output = null;
        },
        .focused_view => |data| {
            seat.updateTitle(data.title);
            if (seat.focusedMonitor()) |monitor| {
                if (monitor.bar) |bar| {
                    if (!bar.configured) {
                        return;
                    }

                    render.renderTitle(bar, seat.window_title) catch |err| {
                        log.err("renderTitle failed for monitor {}: {s}",
                               .{bar.monitor.globalName, @errorName(err)});
                        return;
                    };

                    bar.title.surface.commit();
                    bar.background.surface.commit();
                }
            }
        },
    }
}
