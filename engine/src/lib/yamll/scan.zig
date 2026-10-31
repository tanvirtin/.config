const std = @import("std");
const builtin = @import("builtin");

pub const lanes = 16;
pub const Vec = @Vector(lanes, u8);

pub inline fn splat(c: u8) Vec {
    return @splat(c);
}

pub inline fn bytes(b: @Vector(lanes, bool)) Vec {
    return @select(u8, b, splat(0xff), splat(0));
}

pub inline fn firstSet(m: Vec) ?usize {
    if (comptime builtin.cpu.arch == .aarch64) {
        const wide: @Vector(lanes / 2, u16) = @bitCast(m);
        const nibbles: @Vector(lanes / 2, u8) = @truncate(wide >> @splat(4));
        const bits: u64 = @bitCast(nibbles);
        return if (bits == 0) null else @ctz(bits) >> 2;
    }
    const bits: u16 = @bitCast(m != splat(0));
    return if (bits == 0) null else @ctz(bits);
}

pub inline fn stopBytes(v: Vec) Vec {
    return bytes(v == splat('"')) | bytes(v == splat('\\')) | bytes(v < splat(0x20));
}

pub inline fn quoteOrEscape(v: Vec) Vec {
    return bytes(v == splat('"')) | bytes(v == splat('\\'));
}

pub inline fn anyHigh(acc: Vec) bool {
    return @reduce(.Or, acc) & 0x80 != 0;
}

pub const plain_alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./@+-";

const plain_table = blk: {
    var table: [256]bool = @splat(false);
    for (plain_alphabet) |c| table[c] = true;
    break :blk table;
};

pub inline fn plainChar(c: u8) bool {
    return plain_table[c];
}

pub inline fn flowEnd(c: u8) bool {
    return c == ' ' or c == ',' or c == ']' or c == '}';
}

pub inline fn plainEnd(src: []const u8, from: usize) usize {
    var pos = from;
    while (plainChar(src[pos])) pos += 1;
    return pos;
}

pub inline fn skipSpaces(src: []const u8, from: usize) usize {
    var pos = from;
    while (src[pos] == ' ') pos += 1;
    return pos;
}

inline fn cont(c: u8) bool {
    return c & 0xc0 == 0x80;
}

pub fn validUtf8(text: []const u8) bool {
    var i: usize = 0;
    while (i < text.len) {
        if (i + lanes <= text.len) {
            const v: Vec = text[i..][0..lanes].*;
            i += firstSet(bytes(v >= splat(0x80))) orelse {
                i += lanes;
                continue;
            };
        } else if (text[i] < 0x80) {
            i += 1;
            continue;
        }

        const c = text[i];
        const left = text.len - i;
        switch (c) {
            0xc2...0xdf => {
                if (left < 2 or !cont(text[i + 1])) return false;
                i += 2;
            },
            0xe0...0xef => {
                if (left < 3 or !cont(text[i + 2])) return false;
                const lo: u8, const hi: u8 = switch (c) {
                    0xe0 => .{ 0xa0, 0xbf },
                    0xed => .{ 0x80, 0x9f },
                    else => .{ 0x80, 0xbf },
                };
                if (text[i + 1] < lo or text[i + 1] > hi) return false;
                i += 3;
            },
            0xf0...0xf4 => {
                if (left < 4 or !cont(text[i + 2]) or !cont(text[i + 3])) return false;
                const lo: u8, const hi: u8 = switch (c) {
                    0xf0 => .{ 0x90, 0xbf },
                    0xf4 => .{ 0x80, 0x8f },
                    else => .{ 0x80, 0xbf },
                };
                if (text[i + 1] < lo or text[i + 1] > hi) return false;
                i += 4;
            },
            else => return false,
        }
    }
    return true;
}

pub const no_escape: u16 = 0x100;

pub const simple_escapes = blk: {
    var table: [256]u16 = @splat(no_escape);
    table['n'] = '\n';
    table['t'] = '\t';
    table['\t'] = '\t';
    table['r'] = '\r';
    table['"'] = '"';
    table['\\'] = '\\';
    table['/'] = '/';
    table[' '] = ' ';
    table['0'] = 0;
    table['a'] = 0x07;
    table['b'] = 0x08;
    table['e'] = 0x1b;
    table['f'] = 0x0c;
    table['v'] = 0x0b;
    break :blk table;
};

const testing = std.testing;

test "utf8 validation matches the standard library" {
    const cases = [_][]const u8{ "", "ascii", "caf\u{e9}", "\u{2192}\u{10348}", "\xc0\xaf", "\xe0\x80\xaf", "\xed\xa0\x80", "\xf4\x90\x80\x80", "\xf0\x8f\xbf\xbf", "\xc3", "\xe2\x82", "\x80", "\xff" };
    for (cases) |text| try testing.expectEqual(std.unicode.utf8ValidateSlice(text), validUtf8(text));

    var prng = std.Random.DefaultPrng.init(7);
    const rng = prng.random();
    var buf: [40]u8 = undefined;

    for (0..200_000) |_| {
        const len = rng.uintLessThan(usize, buf.len);
        for (buf[0..len]) |*b| {
            b.* = switch (rng.uintLessThan(u8, 4)) {
                0 => rng.uintLessThan(u8, 0x80),
                1 => 0x80 | rng.uintLessThan(u8, 0x40),
                else => rng.int(u8),
            };
        }
        try testing.expectEqual(std.unicode.utf8ValidateSlice(buf[0..len]), validUtf8(buf[0..len]));
    }
}
