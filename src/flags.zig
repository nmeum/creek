// Zero allocation argument parsing for unix-like systems (taken from River).
// Includes a minor modifications for error handling on unknown flags.
//
// Released under the Zero Clause BSD (0BSD) license:
//
// Copyright 2023 Isaac Freund
//
// Permission to use, copy, modify, and/or distribute this software for any
// purpose with or without fee is hereby granted.
//
// THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

const std = @import("std");
const mem = std.mem;

pub const Flag = struct {
    name: [:0]const u8,
    kind: enum { boolean, arg },
};

pub fn parser(comptime Arg: type, comptime flags: []const Flag) type {
    switch (Arg) {
        // TODO consider allowing []const u8
        [:0]const u8, [*:0]const u8 => {}, // ok
        else => @compileError("invalid argument type: " ++ @typeName(Arg)),
    }
    return struct {
        pub const Result = struct {
            /// Remaining args after the recognized flags
            args: []const Arg,
            /// Data obtained from parsed flags
            flags: Flags,

            pub const Flags = flags_type: {
                var field_names: [flags.len][:0]const u8 = undefined;
                var field_types: [flags.len]type = undefined;
                var field_attrs: [flags.len]std.builtin.Type.Struct.FieldAttributes = undefined;
                for (flags, 0..) |flag, i| {
                    field_names[i] = flag.name;
                    switch (flag.kind) {
                        .boolean => {
                            field_types[i] = bool;
                            field_types[i] = .{
                                .default_value = &false,
                                .@"comptime" = false,
                                .@"align" = @alignOf(bool),
                            };
                        },
                        .arg => {
                            field_types[i] = ?[:0]const u8;
                            field_attrs[i] = .{
                                .default_value_ptr = &@as(?[:0]const u8, null),
                                .@"comptime" = false,
                                .@"align" = @alignOf(?[:0]const u8),
                            };
                        },
                    }
                }
                break :flags_type @Struct(
                    .auto,
                    null,
                    &field_names,
                    &field_types,
                    &field_attrs,
                );
            };
        };

        pub fn parse(args: []const Arg) !Result {
            var result_flags: Result.Flags = .{};

            var i: usize = 0;
            outer: while (i < args.len) : (i += 1) {
                const arg = switch (Arg) {
                    [*:0]const u8 => mem.sliceTo(args[i], 0),
                    [:0]const u8 => args[i],
                    else => unreachable,
                };
                if (arg[0] != '-') {
                    continue;
                }

                var flag_found = false;
                inline for (flags) |flag| {
                    if (mem.eql(u8, "-" ++ flag.name, arg)) {
                        flag_found = true;
                        switch (flag.kind) {
                            .boolean => @field(result_flags, flag.name) = true,
                            .arg => {
                                i += 1;
                                if (i == args.len) {
                                    std.log.err("option '-" ++ flag.name ++
                                        "' requires an argument but none was provided!", .{});
                                    return error.MissingFlagArgument;
                                }
                                @field(result_flags, flag.name) = switch (Arg) {
                                    [*:0]const u8 => mem.sliceTo(args[i], 0),
                                    [:0]const u8 => args[i],
                                    else => unreachable,
                                };
                            },
                        }
                        continue :outer;
                    }
                }
                if (!flag_found) {
                    std.log.err("option '{s}' is unknown", .{arg});
                    return error.UnknownFlag;
                }
                break;
            }

            return Result{
                .args = args[i..],
                .flags = result_flags,
            };
        }
    };
}
