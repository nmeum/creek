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
        .focused_output => |_| {},
        .unfocused_output => |_| {},
        .focused_view => |data| {
            for (state.wayland.monitors.items) |monitor| {
                if (monitor.bar) |bar| {
                    seat.updateTitle(data.title);
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
