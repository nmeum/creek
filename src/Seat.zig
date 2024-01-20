const std = @import("std");
const log = std.log;
const Mutex = std.Thread.Mutex;

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
            seat.mtx.lock();
            defer seat.mtx.unlock();

            if (seat.window_title) |t| {
                state.gpa.free(t);
            }

            const title = std.mem.sliceTo(data.title, 0);
            const vz = state.gpa.allocSentinel(u8, title.len, 0) catch |err| {
                log.err("allocSentinel failed for window title: {s}\n", .{@errorName(err)});
                return;
            };
            std.mem.copy(u8, vz, title);
            seat.window_title = vz;
        },
    }
}
