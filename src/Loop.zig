const std = @import("std");
const log = std.log;
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;
const io = std.io;
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
            .revents = 0,
        },
        .{
            .fd = wayland.fd,
            .events = posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = posix.STDIN_FILENO,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    var readbuffer: [1024]u8 = undefined;
    
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
        if ((fds[2].revents & posix.POLL.IN != 0)) {
            if (state.wayland.river_seat) |seat| {
                if (seat.focusedBar()) |bar| {
                    seat.status_text.reset();
                    // zig-wayland still uses std.io.DeprecatedWriter.
                    var bytes_read: usize = 0;
                    while (bytes_read < readbuffer.len) {
                        var byte: [1]u8 = undefined;
                        const n = posix.read(posix.STDIN_FILENO, &byte) catch |err| {
                            log.err("read failed: {s}", .{@errorName(err)});
                            break;
                        };
                        if (n == 0) break; // EOF
                        if (byte[0] == '\n') break;
                        readbuffer[bytes_read] = byte[0];
                        bytes_read += 1;
                    }

                    std.debug.print("renderText:\n", .{});
                    if(bytes_read > 0) {
                        const line = readbuffer[0..bytes_read];
                        try seat.status_text.writer().writeAll(line);

                        render.renderText(bar, seat.status_text.getWritten()) catch |err| {
                            log.err("renderText failed for monitor {}: {s}",
                                    .{ bar.monitor.globalName, @errorName(err) });
                            continue;
                        };

                        bar.text.surface.commit();
                        bar.background.surface.commit();
                    }
                }
            }
        }
    }
}
