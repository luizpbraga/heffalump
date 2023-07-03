# Heffalump 

Looks like `psycopg`, but we have allocators

![Heffalump](./zzheffalump.jpg "Separados ao nascer")

### Example

```zig
const std = @import("std");
const hefa = @import("heffalump.zig");
const expect = std.testing.expect;

test "Hefallump\n" {
    const allocator = std.testing.allocator;
    const settings = hefa.ConnectionSetting{};

    var conn = try hefa.Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    try cur.execute("drop table if exists Cars;", .{});
    try cur.execute(
        \\create table if not exists Cars(
        \\  id integer primary key,
        \\  name varchar(20),
        \\ price int
        \\);
    , .{});
    try cur.execute("insert into Cars values(1,'Gol',200)", .{});
    try cur.execute("insert into Cars values(2,'Mercedes',57127)", .{});
    try cur.execute("insert into Cars values(3,'Skoda',9000)", .{});
    try cur.execute("insert into Cars values(4,'Volvo',29000)", .{});
    try cur.execute("insert into Cars values(5,'BMW',78000)", .{});

    //
    // The rule is simple: kill the bitch (memory) after using
    //

    const Car = struct {
        id: usize,
        name: []const u8,
        price: usize,
    };

    try cur.execute("select * from Cars", .{});
    {
        var result = try cur.fetch(allocator, Car);
        defer result.deinit();

        for (result.data) |car| {
            try expect(@TypeOf(car) == Car);
            std.debug.print("id: {}, name: {s}, price: ${}\n", .{ car.id, car.name, car.price });
        }
    }

    try cur.execute("select * from Cars where id = 1 or id = 4", .{});
    {
        var record = try cur.fetch(allocator, []const u8);
        defer record.deinit();
        const rows = record.data;
        for (rows, 0..) |row, i| {
            try expect(@TypeOf(row) == []const []const u8);
            std.debug.print("row {}:  {s}\n", .{ i, row });
        }
    }

    try cur.execute("select 1 + 1 + 1", .{});
    {
        var record = try cur.fetch(allocator, usize);
        defer record.deinit();
        const data = record.data[0][0];
        try expect(@TypeOf(data) == usize);
        std.debug.print("{}\n", .{data});
    }

    try cur.execute("select * from Cars", .{});
    {
        var iter = cur.fetchIter(allocator);
        while (try iter.next()) |row| {
            defer allocator.free(row);
            std.debug.print("{s}\n", .{row});
        }
    }
}

```
