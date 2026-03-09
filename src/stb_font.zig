const std = @import("std");
const c = @cImport({
    @cInclude("stb_truetype.h");
});

const BakedFont = struct {
    width: usize,
    height: usize,
    last_row: usize,
    pixels: []const u8,
    first_char: u8,
    num_chars: u8,
    cdata: []c.stbtt_bakedchar,

    fn create(alloc: std.mem.Allocator, font_path: []const u8) !BakedFont {
        const ttf = try std.fs.cwd().openFile(font_path, .{ .mode = .read_only });
        defer ttf.close();

        const data = try ttf.readToEndAlloc(alloc, std.math.maxInt(usize));
        defer alloc.free(data);

        const width = 512;
        const height = 512;
        const first_char = 32;
        const num_chars = 95;

        const pixels = try alloc.alloc(u8, width * height);
        errdefer alloc.free(pixels);

        const cdata = try alloc.alloc(c.stbtt_bakedchar, num_chars);
        errdefer alloc.free(cdata);

        const last_row = c.stbtt_BakeFontBitmap(
            data.ptr,
            0,
            64.0,
            pixels.ptr,
            width,
            height,
            first_char,
            num_chars,
            cdata.ptr,
        );
        std.debug.assert(last_row > 0 and last_row < height);

        return .{
            .width = width,
            .height = height,
            .last_row = @intCast(last_row),
            .pixels = pixels,
            .first_char = first_char,
            .num_chars = num_chars,
            .cdata = cdata,
        };
    }

    fn destory(self: BakedFont, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
        alloc.free(self.cdata);
    }

    fn print_to_ppm(
        self: BakedFont,
        alloc: std.mem.Allocator,
        str: []const u8,
    ) !void {
        const width: usize = 800;
        const height: usize = 600;
        const outbuf = try alloc.alloc(u8, width * height);
        defer alloc.free(outbuf);
        @memset(outbuf, 0);

        var pen_x: isize = 100;
        const pen_y: isize = 100;
        for (str) |ch| {
            const data = self.cdata[ch - self.first_char];
            const ch_w = data.x1 - data.x0;
            const ch_h = data.y1 - data.y0;
            for (0..ch_h) |y| {
                for (0..ch_w) |x| {
                    const gray = self.pixels[(y + data.y0) * self.width + x + data.x0];
                    const xoff: isize = @intFromFloat(data.xoff);
                    const yoff: isize = @intFromFloat(data.yoff);
                    const i = (pen_y + @as(isize, @intCast(y)) + yoff) * width + pen_x + @as(isize, @intCast(x)) + xoff;
                    outbuf[@intCast(i)] = gray;
                }
            }
            pen_x += @intFromFloat(@ceil(data.xadvance));
        }

        const outfile = try std.fs.cwd().createFile("output.ppm", .{ .truncate = true, .mode = 0o644 });
        defer outfile.close();

        var file_buf: [1024]u8 = undefined;
        var file_writer = outfile.writer(&file_buf);
        const writer = &file_writer.interface;

        try writer.print("P3\n{d} {d}\n255\n", .{ width, height });
        for (0..height) |y| {
            for (0..width) |x| {
                const gray = outbuf[y * width + x];
                try writer.print("{d} {d} {d} ", .{ gray, gray, gray });
            }
            try writer.writeByte('\n');
        }
        try writer.flush();

        std.debug.print("{s} printed into ppm file\n", .{str});
    }
};

test "process" {
    const font_path = "assets/Roboto-Regular.ttf";
    const font = try BakedFont.create(std.testing.allocator, font_path);
    defer font.destory(std.testing.allocator);

    try font.print_to_ppm(std.testing.allocator, "hello, world!");
}
