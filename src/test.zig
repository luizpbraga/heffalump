const std = @import("std");
const testing = std.testing;
const hefallump = @import("heffalump.zig");

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

test "main" {
    const allocator = std.testing.allocator;
    const settings = hefallump.ConnectionSetting{};

    var conn = try hefallump.Connection.init(&settings);
    defer conn.close();

    var cur = conn.cursor();
    defer cur.close();

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

    // The rule is simple: kill after using
    try cur.execute("select * from Cars", .{});
    {
        var record = try cur.fetchAll(allocator);
        defer record.deinit();
        const rows = record.data;
        for (rows) |row|
            std.debug.print("{s}\n", .{row});
    }

    try cur.execute("select 1 + 1 + 1", .{});
    {
        var record = try cur.fetchAll(allocator);
        defer record.deinit();
        const data = record.data[0][0];
        std.debug.print("{s}\n", .{data});
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
