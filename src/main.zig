const clap = @import("zig-clap");
const std = @import("std");

const base64 = std.base64;
const crypto = std.crypto;
const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const os = std.os;

const Clap = clap.ComptimeClap([]const u8, params);
const Names = clap.Names;
const Param = clap.Param([]const u8);

const base64_encoder = base64.Base64Encoder.init("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+=", '!');

const params = [_]Param{
    Param{
        .id = "display this help text and exit",
        .names = Names{ .short = 'h', .long = "help" },
    },
    Param{
        .id = "override the folder used to stored temporary files",
        .names = Names{ .short = 't', .long = "tmp" },
        .takes_value = true,
    },
    Param{
        .id = "print commands before executing them",
        .names = Names{ .short = 'v', .long = "verbose" },
    },
    Param{
        .id = "override the path to the Zig executable",
        .names = Names{ .long = "zig" },
        .takes_value = true,
    },
    Param{
        .id = "",
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.write(
        \\Usage: hacky-zig-repl [OPTION]...
        \\Allows repl like functionality for Zig.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, params);
}

const repl_template = @embedFile("template.zig");

pub fn main() anyerror!void {
    @setEvalBranchQuota(10000);

    const stdout = &(try io.getStdOut()).outStream().stream;
    const stderr = &(try io.getStdErr()).outStream().stream;

    var da = std.heap.DirectAllocator.init();
    defer da.deinit();

    var arg_iter = clap.args.OsIterator.init(&da.allocator);
    _ = arg_iter.next() catch undefined;

    var args = Clap.parse(&da.allocator, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const zig_path = args.option("--zig") orelse "zig";
    const tmp_dir = args.option("--tmp") orelse "/tmp";
    const verbose = args.flag("--verbose");

    var last_run_buf = try std.Buffer.initSize(&da.allocator, 0);
    var line_buf = try std.Buffer.initSize(&da.allocator, 0);
    var i: usize = 0;
    while (true) : (line_buf.shrink(0)) {
        const last_run = last_run_buf.toSlice();
        var arena = heap.ArenaAllocator.init(&da.allocator);
        defer arena.deinit();

        const allocator = &arena.allocator;

        try stdout.write(">> ");
        const line = mem.trim(u8, try io.readLine(&line_buf), " \t");
        if (line.len == 0)
            continue;

        const assignment = try fmt.allocPrint(allocator, "const _{} = {};\n", i, line);

        var crypt_src: [224/8]u8 = undefined;
        crypto.Blake2s224.hash(last_run, crypt_src[0..]);

        var encoded_src: [base64.Base64Encoder.calcSize(crypt_src.len)]u8 = undefined;
        base64_encoder.encode(encoded_src[0..], crypt_src);

        const file_name = try fmt.allocPrint(allocator, "{}/{}.zig", tmp_dir, encoded_src);
        if (verbose)
            debug.warn("writing source to '{}'\n", file_name);

        const file = try std.fs.File.openWrite(file_name);
        defer file.close();
        const stream = &file.outStream().stream;
        try stream.print(repl_template, last_run, assignment, i, i);

        if (verbose)
            debug.warn("running command '{} run {}'\n", zig_path, file_name);
        run(allocator, [_][]const u8{
            zig_path,
            "run",
            file_name,
        }) catch |err| {
            debug.warn("error: {}\n", err);
            continue;
        };

        try last_run_buf.append(assignment);
        i += 1;
    }
}

fn run(allocator: *mem.Allocator, argv: []const []const u8) !void {
    const process = try std.ChildProcess.init(argv, allocator);
    defer process.deinit();

    try process.spawn();
    switch (try process.wait()) {
        std.ChildProcess.Term.Exited => |code| {
            if (code != 0)
                return error.ProcessFailed;
        },
        else => return error.ProcessFailed,
    }
}
