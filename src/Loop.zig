const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;
const io = std.io;

const render = @import("render.zig");
const Loop = @This();

const state = &@import("root").state;

sfd: os.fd_t,

pub fn init() !Loop {
    var mask = os.empty_sigset;
    os.linux.sigaddset(&mask, os.linux.SIG.INT);
    os.linux.sigaddset(&mask, os.linux.SIG.TERM);
    os.linux.sigaddset(&mask, os.linux.SIG.QUIT);

    _ = os.linux.sigprocmask(os.linux.SIG.BLOCK, &mask, null);
    const sfd = os.linux.signalfd(-1, &mask, os.linux.SFD.NONBLOCK);

    return Loop{ .sfd = @intCast(os.fd_t, sfd) };
}

pub fn run(self: *Loop) !void {
    const wayland = &state.wayland;

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
            .fd = os.STDIN_FILENO,
            .events = os.POLL.IN,
            .revents = undefined,
        },
    };

    var reader = io.getStdIn().reader();
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

        // status input
        if (fds[2].revents & os.POLL.IN != 0) {
            for (state.wayland.monitors.items) |monitor| {
                if (monitor.bar) |bar| {
                    if (!bar.configured) {
                        continue;
                    }

                    var buf: [4096]u8 = undefined;
                    var line = try reader.readUntilDelimiter(&buf, '\n');

                    render.renderText(bar, line) catch |err| {
                        log.err("renderText failed for monitor {}: {s}",
                            .{monitor.globalName, @errorName(err)});
                        continue;
                    };

                    bar.text.surface.commit();
                    bar.background.surface.commit();
                }
            }
        }
    }
}
