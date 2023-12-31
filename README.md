# Heffalump 

Looks like `psycopg`, but we have allocators

![Heffalump](./zzheffalump.jpg "Separados ao nascer")

### Build

In your `build.zig` add
```zig
pub fn build(b: *std.Build) !void {
    //...
    const heffalump = b.dependency("heffalump", .{
            .target = target,
            .optimize = optimize,
        });

        exe.addModule("heffalump", heffalump.module("heffalump"));
        exe.linkLibrary(heffalump.artifact("heffalump"));
        
    // ...
        b.installArtifact(exe);
```

and the `build.zig.zon` should look like this
```
.{
    // ...
    .dependencies = .{
        // ...
        .heffalump = .{
            .url = "https://github.com/luizpbraga/heffalump/archive/refs/tags/v0.0.1.tar.gz",
            .hash = "122043f5d763462a23e11375f2d5938ad41651aad6e9c3b2f688f07be81ee59f1390",
        },
    }
}

```

then run `zig build`.

### Example

```zig
const std = @import("std");
const heffa = @import("heffalump"); // no '.zig' here
const getenv = std.os.getenv;
const expect = std.testing.expect;
const allocator = std.testing.allocator;

test "Hefallump test" {

    //
    // Database settings
    //
    const settings = heffa.ConnectionSetting{
        .port = getenv("DB_PORT"),
        .user = getenv("DB_USER"),
        .host = getenv("DB_HOST"),
        .dbname = getenv("DB_NAME"),
        .password = getenv("DB_PASSWORD"),
    };

    //
    // Start the connection
    //
    var conn = try heffa.Connection.init(&settings);
    defer conn.deinit();

    //
    // Start the cursor
    //
    var cur = conn.cursor();
    defer cur.deinit();

    //
    // let's run some queries
    //
    try cur.execute("DROP TABLE IF EXISTS Cars;", .{});
    try cur.execute(
        \\CREATE TABLE IF NOT EXISTS Cars(
        \\  id      INTEGER PRIMARY KEY,
        \\  name    VARCHAR(20),
        \\  price   INTEGER
        \\);
    , .{});
    try cur.execute("INSERT INTO CARS VALUES(1,'Gol',200)", .{});
    try cur.execute("INSERT INTO CARS VALUES(2,'Mercedes',57127)", .{});
    try cur.execute("INSERT INTO CARS VALUES(3,'Skoda',9000)", .{});
    try cur.execute("INSERT INTO CARS VALUES(4,'Volvo',29000)", .{});
    try cur.execute("INSERT INTO CARS VALUES(5,'BMW',78000)", .{});

    //
    // The rule is simple: kill the bitch (memory) after using
    //

    const Car = struct {
        id: usize,
        name: []const u8,
        price: usize,
    };

    try cur.execute("SELECT * FROM Cars", .{});
    {
        var result = try cur.fetch(allocator, Car);
        defer result.deinit();

        for (result.data) |car| {
            try expect(@TypeOf(car) == Car);
            std.debug.print("id: {}, name: {s}, price: ${}\n", .{ car.id, car.name, car.price });
        }
    }

    try cur.execute("SELECT * FROM Cars WHERE id = 1 OR id = 4", .{});
    {
        var record = try cur.fetch(allocator, []const u8);
        defer record.deinit();
        const rows = record.data;
        for (rows, 0..) |row, i| {
            try expect(@TypeOf(row) == []const []const u8);
            std.debug.print("row {}:  {s}\n", .{ i, row });
        }
    }

    try cur.execute("SELECT 1 + 1 + 1", .{});
    {
        var record = try cur.fetch(allocator, usize);
        defer record.deinit();
        const data = record.data[0][0];
        try expect(@TypeOf(data) == usize);
        std.debug.print("{}\n", .{data});
    }

    try cur.execute("SELECT * FROM Cars", .{});
    {
        var iter = cur.fetchIter(allocator);
        while (try iter.next()) |row| {
            defer allocator.free(row);
            std.debug.print("{s}\n", .{row});
        }
    }
}

```
