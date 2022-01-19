const std = @import("std");
const mem = std.mem;
const os = std.os;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;

const State = @import("main.zig").State;

pub const Loop = struct {
    state: *State,

    fds: [2]os.pollfd,
    timers: ArrayList(*Timer),

    pub fn init(state: *State) !Loop {
        const tfd = os.linux.timerfd_create(
            os.CLOCK.MONOTONIC,
            os.linux.TFD.CLOEXEC,
        );

        return Loop{
            .state = state,
            .fds = .{
                .{
                    .fd = state.wayland.display.getFd(),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
                .{
                    .fd = @intCast(os.fd_t, tfd),
                    .events = os.POLL.IN,
                    .revents = 0,
                },
            },
            .timers = ArrayList(*Timer).init(state.allocator),
        };
    }

    pub fn run(self: *Loop) !void {
        const display = self.state.wayland.display;

        while (true) loop: {
            while (true) {
                const ret = try display.dispatchPending();
                _ = try display.flush();
                if (ret <= 0) break;
            }
            _ = try os.poll(&self.fds, -1);

            for (self.fds) |fd| {
                if (fd.revents & os.POLL.HUP != 0) {
                    break :loop;
                }
                if (fd.revents & os.POLL.ERR != 0) {
                    break :loop;
                }
            }

            // wayland
            if (self.fds[0].revents & os.POLL.IN != 0) {
                _ = try display.dispatch();
            }
            if (self.fds[0].revents & os.POLL.OUT != 0) {
                _ = try display.flush();
            }

            // timer
            if (self.fds[1].revents & os.POLL.IN != 0) {
                for (self.timers.items) |timer, i| {
                    const callback = timer.callback;
                    const payload = timer.payload;
                    _ = self.timers.swapRemove(i);
                    callback(payload);
                }
            }
        }
    }
};

pub const Timer = struct {
    callback: fn (*anyopaque) void,
    payload: *anyopaque,
};
