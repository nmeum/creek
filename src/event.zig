const std = @import("std");
const mem = std.mem;
const os = std.os;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;

const render = @import("render.zig");
const State = @import("main.zig").State;

pub const Loop = struct {
    state: *State,
    fds: [2]os.pollfd,

    pub fn init(state: *State) !Loop {
        const tfd = os.linux.timerfd_create(
            os.CLOCK.MONOTONIC,
            os.linux.TFD.CLOEXEC,
        );
        const interval: os.linux.itimerspec = .{
            .it_interval = .{ .tv_sec = 1, .tv_nsec = 0 },
            .it_value = .{ .tv_sec = 1, .tv_nsec = 0 },
        };
        _ = os.linux.timerfd_settime(@intCast(i32, tfd), 0, &interval, null);

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
        };
    }

    pub fn run(self: *Loop) !void {
        const display = self.state.wayland.display;
        const tfd = self.fds[1].fd;

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
                var expirations = mem.zeroes([8]u8);
                _ = try os.read(tfd, &expirations);

                for (self.state.wayland.outputs.items) |output| {
                    if (output.surface) |surface| {
                        if (surface.configured) {
                            render.renderClock(surface) catch continue;
                            surface.clockSurface.commit();
                            surface.backgroundSurface.commit();
                        }
                    }
                }
            }
        }
    }
};
