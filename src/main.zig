const clap = @import("zig-clap");
const std = @import("std");

const base64 = std.base64;
const crypto = std.crypto;
const debug = std.debug;
const fmt = std.fmt;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const math = std.math;
const mem = std.mem;
const os = std.os;

const Clap = clap.ComptimeClap(clap.Help, &params);
const Names = clap.Names;
const Param = clap.Param(clap.Help);

const params = [_]Param{
    clap.parseParam("-h, --help       display this help text and exit                   ") catch unreachable,
    clap.parseParam("-t, --tmp <DIR>  override the folder used to stored temporary files") catch unreachable,
    clap.parseParam("-v, --verbose    print commands before executing them              ") catch unreachable,
    clap.parseParam("    --zig <EXE>  override the path to the Zig executable           ") catch unreachable,
    Param{
        .takes_value = true,
    },
};

fn usage(stream: var) !void {
    try stream.writeAll(
        \\Usage: hacky-zig-repl [OPTION]...
        \\Allows repl like functionality for Zig.
        \\
        \\Options:
        \\
    );
    try clap.help(stream, &params);
}

const repl_template =
    \\usingnamespace @import("std");
    \\pub fn main() !void {{
    \\{}
    \\{}
    \\    try __repl_print_stdout(_{});
    \\}}
    \\
    \\fn __repl_print_stdout(v: var) !void {{
    \\    const stdout = io.getStdOut().outStream();
    \\    try stdout.writeAll("_{} = ");
    \\    try fmt.formatType(
    \\        v,
    \\        "",
    \\        fmt.FormatOptions{{}},
    \\        stdout,
    \\        3,
    \\    );
    \\    try stdout.writeAll("\n");
    \\}}
    \\
;

pub fn main() anyerror!void {
    @setEvalBranchQuota(10000);

    const stdin = io.getStdIn().inStream();
    const stdout = io.getStdOut().outStream();
    const stderr = io.getStdErr().outStream();

    const pa = std.heap.page_allocator;
    var arg_iter = try clap.args.OsIterator.init(pa);
    var args = Clap.parse(pa, clap.args.OsIterator, &arg_iter) catch |err| {
        usage(stderr) catch {};
        return err;
    };

    if (args.flag("--help"))
        return try usage(stdout);

    const zig_path = args.option("--zig") orelse "zig";
    const tmp_dir = args.option("--tmp") orelse "/tmp";
    const verbose = args.flag("--verbose");

    var last_run_buf = std.ArrayList(u8).init(pa);
    var line_buf = std.ArrayList(u8).init(pa);
    var i: usize = 0;
    while (true) : (line_buf.shrink(0)) {
        const last_run = last_run_buf.items;
        var arena = heap.ArenaAllocator.init(pa);
        defer arena.deinit();

        const allocator = &arena.allocator;

        // TODO: proper readline prompt
        try stdout.writeAll(">> ");
        stdin.readUntilDelimiterArrayList(&line_buf, '\n', math.maxInt(usize)) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const line = mem.trim(u8, line_buf.items, " \t");
        if (line.len == 0)
            continue;

        const assignment = try fmt.allocPrint(allocator, "const _{} = {};\n", .{ i, line });

        var crypt_src: [224 / 8]u8 = undefined;
        crypto.Blake2s224.hash(last_run, &crypt_src);

        var encoded_src: [base64.Base64Encoder.calcSize(crypt_src.len)]u8 = undefined;
        fs.base64_encoder.encode(&encoded_src, &crypt_src);

        const file_name = try fmt.allocPrint(allocator, "{}/{}.zig", .{ tmp_dir, &encoded_src });
        if (verbose)
            debug.warn("writing source to '{}'\n", .{file_name});

        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.outStream().print(repl_template, .{ last_run, assignment, i, i });

        if (verbose)
            debug.warn("running command '{} run {}'\n", .{ zig_path, file_name });
        run(allocator, &[_][]const u8{ zig_path, "run", file_name }) catch |err| {
            debug.warn("error: {}\n", .{err});
            continue;
        };

        try last_run_buf.appendSlice(assignment);
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
