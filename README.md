# Heffalump

It's [`libpq`](https://www.postgresql.org/docs/current/libpq.html) but we have allocators (and no async). Please, don't use this module in production.

The go is make _Postgres_ more comfortable for zig user, introducing a better style
for `libpq` (no implicit _exit(1)_, God please). See the [examples](#example).

![Heffalump](./zzheffalump.jpg "Separados ao nascer")

### Build

In your `build.zig`, add the `heffalump` module as a dependency

```zig
pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        // ...
    });

    // *** create a dependency and import it ***
    const heffalump = b.dependency("heffalump", .{});
    exe.root_module.addImport("heffalump", heffalump.module("heffalump"));

    // ...
    b.installArtifact(exe);
    // ...
}
```

And the `build.zig.zon` should look like this

```
.{
    // ...
    .dependencies = .{
        // Last version
        .heffalump = .{
            .url = "https://github.com/luizpbraga/heffalump/archive/refs/tags/v0.0.1.1.tar.gz",
            .hash = "122004985da631572a7255ec5d5f726af64790d922c5bd2da4ea2eb34ec91e16e42c",
        },
    },
}
```

Then run `zig build`.

> WARNING: You need `libpq`;

### Example

```zig
const std = @import("std");
const heffa = @import("heffalump"); // no '.zig' here
const ally = std.testing.allocator;

test "Hefallump Examples" {
    //
    // Database settings
    //
    const dsn = "user=postgres password=postgres dbname=testdb host=localhost";

    //
    // Start The Connection
    //
    var conn = try heffa.Connection.init(ally, dsn);
    defer conn.deinit();

    //
    // Append Some Data
    //
    try conn.run("DROP TABLE IF EXISTS cars;", .{});

    try conn.run(
        \\CREATE TABLE IF NOT EXISTS cars (
        \\    id    SERIAL PRIMARY KEY,
        \\    name  VARCHAR(20),
        \\    price INT
        \\)
    , .{});

    try conn.run(
        \\INSERT INTO cars (name, price) VALUES
        \\  ('Gol', 200),
        \\  ('BMW', 78000),
        \\  ('Skoda', 9000),
        \\  ('Volvo', 29000),
        \\  ('Mercedes', 57127)
    , .{});

    //
    // Fetch Some Data
    //
    var result = try conn.exec(
        "SELECT id, price, name FROM cars", .{}
    );
    defer result.deinit();

    //
    // Iterate Over The Data
    //
    var rows = result.rows(ally); // TODO: remove this allocations [only structs are allocated]
    defer rows.deinit()
    while (rows.next()) |row| {
        var id: u8 = undefined;
        var price: usize = undefined;
        var name: []const u8 = undefined;
        try row.scan(.{ &id, &name, &price });

        std.debug.print("id: {}, name: {s}, price: {}\n", .{ id, name, price });

        // INFO: This API is in the plans
        // const car = try row.from(struct { id: u8, price: usize, name: []const u8 });
    }

    //
    // Get A Specific Row by name or index
    //
    const row_zero = 0;
    const row = try result.getRow(row_zero);
    const id = try row.get(u8, "id");
    const name = try row.get([]const u8, 2);
    std.debug.print("row: {} id: {}, name: {s}\n", .{ row_zero, id, name});

    //
    //  Update Some Data With Parameters
    //
    const query = "INSERT INTO cars (name, price) VALUES ($1, $2)";
    const values = .{
        "Savero",
        "322",          //INFO: See conn.execBin() to use 332 as comptime_int
    };
    try conn.run(query, values);

    //
    // Transaction
    //
    var tx = try conn.beginTx();
    defer tx.commit() catch unreachable;

    try tx.run(
        \\INSERT INTO cars (name, price) VALUES
        \\  ('HB20', 7000)
    , .{});

    // if some random shit happened
    if (true) try conn.rollBack();
}
```
