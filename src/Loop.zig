const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;

const State = @import("main.zig").State;
const utils = @import("utils.zig");
const Loop = @This();

state: *State,
sfd: os.fd_t,

pub fn init(state: *State) !Loop {
    var mask = os.empty_sigset;
    os.linux.sigaddset(&mask, os.linux.SIG.INT);
    os.linux.sigaddset(&mask, os.linux.SIG.TERM);
    os.linux.sigaddset(&mask, os.linux.SIG.QUIT);

    _ = os.linux.sigprocmask(os.linux.SIG.BLOCK, &mask, null);
    const sfd = os.linux.signalfd(-1, &mask, os.linux.SFD.NONBLOCK);

    return Loop{ .state = state, .sfd = @intCast(os.fd_t, sfd) };
}

pub fn run(self: *Loop) !void {
    const wayland = &self.state.wayland;
    const modules = &self.state.modules;

    var fds = [_]os.pollfd{
        .{
            .fd = self.sfd,
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = wayland.fd,
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = if (modules.backlight) |mod| mod.fd else -1,
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = if (modules.battery) |mod| mod.fd else -1,
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = if (modules.pulse) |mod| mod.fd else -1,
            .events = os.POLL.IN,
            .revents = undefined,
        },
    };

    while (true) {
        while (true) {
            const ret = wayland.display.dispatchPending();
            _ = wayland.display.flush();
            if (ret == .SUCCESS) break;
        }

        _ = os.poll(&fds, -1) catch |err| {
            log.err("poll failed: {s}", .{@errorName(err)});
            return;
        };

        for (fds) |fd| {
            if (fd.revents & os.POLL.HUP != 0 or fd.revents & os.POLL.ERR != 0) {
                return;
            }
        }

        // signals
        if (fds[0].revents & os.POLL.IN != 0) {
            return;
        }

        // wayland
        if (fds[1].revents & os.POLL.IN != 0) {
            const errno = wayland.display.dispatch();
            if (errno != .SUCCESS) return;
        }
        if (fds[1].revents & os.POLL.OUT != 0) {
            const errno = wayland.display.flush();
            if (errno != .SUCCESS) return;
        }

        // modules
        if (modules.backlight) |*mod| if (fds[2].revents & os.POLL.IN != 0) {
            log.info("backlight", .{});
            mod.refresh() catch return;
        };
        if (modules.battery) |*mod| if (fds[3].revents & os.POLL.IN != 0) {
            log.info("battery", .{});
            mod.refresh() catch return;
        };
        if (modules.pulse) |*mod| if (fds[4].revents & os.POLL.IN != 0) {
            log.info("pulse", .{});
            mod.refresh() catch return;
        };
    }
}
