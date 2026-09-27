const std = @import("std");

const CHUNK: u64 = 65536;
var N: u64 = 0;
var E: usize = 0;
var partials: []align(64) f64 = undefined;

inline fn fluid(i: u64) f64 {
    return -0.375 + @as(f64, @floatFromInt((i * 31 + 11) & 2047)) * (1.0 / 2048.0);
}

inline fn solid(i: u64) f64 {
    return 0.25 + @as(f64, @floatFromInt((i * 23 + 5) & 1023)) * (1.0 / 1536.0);
}

inline fn rho(i: u64) f64 {
    return 1.0 + @as(f64, @floatFromInt((i * 13 + 9) & 255)) * (1.0 / 2048.0);
}

inline fn mu(i: u64) f64 {
    return 0.75 + @as(f64, @floatFromInt((i * 7 + 3) & 127)) * (1.0 / 1024.0);
}

inline fn elastic(i: u64) f64 {
    return 1.25 + @as(f64, @floatFromInt((i * 19 + 1) & 255)) * (1.0 / 1024.0);
}

inline fn gammaC(i: u64) f64 {
    return 0.125 + @as(f64, @floatFromInt((i * 5 + 7) & 63)) * (1.0 / 4096.0);
}

inline fn slot(i: u64) f64 {
    @setFloatMode(.optimized);
    const im1 = if (i != 0) i - 1 else N - 1;
    const ip1 = if (i + 1 != N) i + 1 else 0;

    const fi = fluid(i);
    const fm = fluid(im1);
    const fp = fluid(ip1);
    const ui = solid(i);
    const um = solid(im1);
    const up = solid(ip1);

    var f = rho(i) * (2.0 * fi - fm - fp) + mu(i) * (fp - fm);
    var s = elastic(i) * (2.0 * ui - um - up) + 0.0625 * (up - um);
    const g = gammaC(i);
    const d = fi - ui;
    f += g * d;
    s -= g * d;
    return f * f + s * s;
}

fn chunkSum(k: u64) f64 {
    @setFloatMode(.optimized);
    const start = k * CHUNK;
    const end = @min(start + CHUNK, N);
    var a0: f64 = 0.0;
    var a1: f64 = 0.0;
    var a2: f64 = 0.0;
    var a3: f64 = 0.0;
    var i = start;
    while (i + 4 <= end) : (i += 4) {
        a0 += slot(i);
        a1 += slot(i + 1);
        a2 += slot(i + 2);
        a3 += slot(i + 3);
    }
    if (i < end) { a0 += slot(i); i += 1; }
    if (i < end) { a1 += slot(i); i += 1; }
    if (i < end) { a2 += slot(i); }
    return (a0 + a1) + (a2 + a3);
}

fn worker(e: usize) void {
    const chunks = (N + CHUNK - 1) / CHUNK;
    var k: u64 = @intCast(e);
    while (k < chunks) : (k += @intCast(E)) {
        partials[@intCast(k)] = chunkSum(k);
    }
}

fn treeReduce(m0: u64) f64 {
    @setFloatMode(.optimized);
    var m = m0;
    while (m > 1) {
        var w: u64 = 0;
        var i: u64 = 0;
        while (i + 1 < m) : (i += 2) {
            partials[@intCast(w)] = partials[@intCast(i)] + partials[@intCast(i + 1)];
            w += 1;
        }
        if ((m & 1) != 0) {
            partials[@intCast(w)] = partials[@intCast(m - 1)];
            w += 1;
        }
        m = w;
    }
    return partials[0];
}

pub fn main(init: std.process.Init) !u8 {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return 2;

    N = std.fmt.parseInt(u64, args[1], 10) catch return 2;
    E = std.fmt.parseInt(usize, args[2], 10) catch return 2;
    if (N < 4 or N > 100_000_000 or (E != 1 and E != 2 and E != 4)) return 2;

    const chunks = (N + CHUNK - 1) / CHUNK;
    partials = try init.gpa.alignedAlloc(f64, .@"64", @intCast(chunks));
    defer init.gpa.free(partials);

    if (E == 1) {
        worker(0);
    } else {
        var threads: [4]std.Thread = undefined;
        for (0..E) |e| threads[e] = try std.Thread.spawn(.{}, worker, .{e});
        for (threads[0..E]) |thread| thread.join();
    }

    const out = treeReduce(chunks);
    const bits: u64 = @bitCast(out);
    std.debug.print("checksum_bits=0x{x:0>16}\n", .{bits});
    return 0;
}
