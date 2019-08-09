use @import("std");
pub fn main() !void {{
{}
{}
    try __repl_print_stdout(_{});
}}

fn __repl_print_stdout(v: var) !void {{
    const stdout = &(try io.getStdOut()).outStream().stream;
    try stdout.write("_{} = ");
    try fmt.formatType(
        v,
        "",
        fmt.FormatOptions{{}},
        stdout,
        fs.File.OutStream.Error,
        stdout.writeFn,
        3,
    );
    try stdout.print("\n");
}}
