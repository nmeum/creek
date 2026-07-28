const std = @import("std");
const log = std.log;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const Io = std.Io;
const fs = std.fs;

const render = @import("render.zig");
const Loop = @This();

const state = &@import("root").state;

sfd: posix.fd_t,

pub fn init() !Loop {
    var mask = linux.sigemptyset();
    linux.sigaddset(&mask, linux.SIG.INT);
    linux.sigaddset(&mask, linux.SIG.TERM);
    linux.sigaddset(&mask, linux.SIG.QUIT);

    _ = linux.sigprocmask(linux.SIG.BLOCK, &mask, null);
    const sfd = linux.signalfd(-1, &mask, linux.SFD.NONBLOCK);

    return Loop{ .sfd = @intCast(sfd) };
}

pub fn run(self: *Loop) !void {
    const wayland = &state.wayland;

    var fds = [_]posix.pollfd{
        .{
            .fd = self.sfd,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = wayland.fd,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
        .{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = undefined,
        },
    };

    var readbuffer: [1024]u8 = undefined;
    var reader = Io.File.stdin().reader(state.io, &readbuffer);
    while (true) {
        while (true) {
            const ret = wayland.display.dispatchPending();
            _ = wayland.display.flush();
            if (ret == .SUCCESS) break;
        }

        _ = posix.poll(&fds, -1) catch |err| {
            log.err("poll failed: {s}", .{@errorName(err)});
            return;
        };

        for (fds) |fd| {
            if (fd.revents & posix.POLL.HUP != 0 or fd.revents & posix.POLL.ERR != 0) {
                return;
            }
        }

        // signals
        if (fds[0].revents & posix.POLL.IN != 0) {
            return;
        }

        // wayland
        if (fds[1].revents & posix.POLL.IN != 0) {
            const errno = wayland.display.dispatch();
            if (errno != .SUCCESS) return;
        }
        if (fds[1].revents & posix.POLL.OUT != 0) {
            const errno = wayland.display.flush();
            if (errno != .SUCCESS) return;
        }

        // status input
        if (fds[2].revents & posix.POLL.IN != 0) {
            if (state.wayland.river_seat) |seat| {
                if (seat.focusedBar()) |bar| {
                    seat.status_text.end = 0;
                    _ = reader.interface.streamDelimiter(&seat.status_text, '\n') catch |err| switch (err) {
                        error.EndOfStream => return,
                        else => |e| return e,
                    };
                    reader.interface.toss(1);

                    render.renderText(bar, seat.status_text.buffered()) catch |err| {
                        log.err("renderText failed for monitor {}: {s}", .{ bar.monitor.globalName, @errorName(err) });
                        continue;
                    };

                    bar.text.surface.commit();
                    bar.background.surface.commit();
                }
            }
        }
    }
}
