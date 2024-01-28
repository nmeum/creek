const std = @import("std");
const log = std.log;
const Mutex = std.Thread.Mutex;

const render = @import("render.zig");
const zriver = @import("wayland").client.zriver;
const state = &@import("root").state;

pub const Seat = @This();

seat_status: *zriver.SeatStatusV1,
window_title: ?[:0]u8,
mtx: Mutex,

pub fn create() !*Seat {
    const self = try state.gpa.create(Seat);
    const manager = state.wayland.status_manager.?;
    const seat = state.wayland.seat_wl.?;

    self.mtx = Mutex{};
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

fn seatListener(
    _: *zriver.SeatStatusV1,
    event: zriver.SeatStatusV1.Event,
    seat: *Seat,
) void {
    switch (event) {
        .focused_output => |_| {},
        .unfocused_output => |_| {},
        .focused_view => |data| {
            for (state.wayland.monitors.items) |monitor| {
                if (monitor.bar) |bar| {
                    var title = std.mem.sliceTo(data.title, 0);

                    seat.mtx.lock();
                    if (seat.window_title) |t| {
                        state.gpa.free(t);
                    }
                    if (title.len == 0) {
                        seat.window_title = null;
                    } else {
                        const vz = state.gpa.allocSentinel(u8, title.len, 0) catch |err| {
                            log.err("allocSentinel failed for window title: {s}\n", .{@errorName(err)});
                            return seat.mtx.unlock();
                        };
                        std.mem.copy(u8, vz, title);
                        seat.window_title = vz;
                    }
                    seat.mtx.unlock();

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
