use @import("std");
pub fn main() !void {{
{}
{}
    try __repl_print_stdout(_{});
}}

fn __repl_print_stdout(v: var) !void {{
    const stdout = &(try io.getStdOut()).outStream().stream;
    try stdout.print("_{} = ");
    try fmt.formatType(
        v,
        "",
        stdout,
        os.File.OutStream.Error,
        stdout.writeFn,
    );
    try stdout.print("\n");
}}
