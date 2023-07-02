# Heffalump 

![Heffalump](./zheffalump.jpg "Separados ao nascer")

### Example

```zig
const std = @impot("std");
const heffalump = @impot("heffalump");

test "Heffalump" {
    const allocator = std.testing.allocator;
    const settings = heffalump.ConnectionSetting{};

    var conn = try heffalump.Connection.init(&settings);
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

    //
    // The rule is simple: kill the bitch after using
    //

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
```
