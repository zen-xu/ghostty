const std = @import("std");
const fc = @cImport({
    @cInclude("fontconfig/fontconfig.h");
});

// Set to true when FontConfig is initialized.
var initialized: bool = false;

pub fn list() !void {
    if (!initialized) {
        if (fc.FcInit() != fc.FcTrue) {
            return error.InitializionFailed;
        }
    }

    const pat = fc.FcPatternCreate();
    defer fc.FcPatternDestroy(pat);

    const key = fc.FC_FULLNAME;
    const os = fc.FcObjectSetBuild(
        key,
        @as([*c]const u8, 0), // @as required Zig #1481
    );
    defer fc.FcObjectSetDestroy(os);

    const fs = fc.FcFontList(null, pat, os);
    defer fc.FcFontSetDestroy(fs);

    var i: usize = 0;
    while (i <= fs.*.nfont) : (i += 1) {
        const fpat = fs.*.fonts[i];
        var str: [*c]fc.FcChar8 = undefined;
        if (fc.FcPatternGetString(fpat, key, 0, &str) == fc.FcResultMatch) {
            std.log.info("FONT: {s}", .{
                @ptrCast([*:0]u8, str),
            });
        }
    }
}
