const fcft = @import("fcft");
const pixman = @import("pixman");

pub const Config = struct {
    height: u16,
    backgroundColor: pixman.Color,
    foregroundColor: pixman.Color,
    border: u15,
    font: *fcft.Font,

    pub fn init() !Config {
        var font_names = [_][*:0]const u8{"monospace:size=14"};

        return Config{
            .height = 32,
            .backgroundColor = .{
                .red = 0,
                .green = 0,
                .blue = 0,
                .alpha = 0xffff,
            },
            .foregroundColor = .{
                .red = 0xffff,
                .green = 0xffff,
                .blue = 0xffff,
                .alpha = 0xffff,
            },
            .border = 2,
            .font = try fcft.Font.fromName(&font_names, null),
        };
    }
};
