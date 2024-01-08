const std = @import("std");
const heffa = @import("heffalump");
const ally = std.testing.allocator;

const Car = struct {
    name: []const u8,
    id: u8,
    price: usize,
};

const N_COLS = 3;
const N_ROWS = 5;
const corrent_result: []const Car = &.{
    .{ .id = 1, .name = "Gol", .price = 200 },
    .{ .id = 2, .name = "BMW", .price = 78000 },
    .{ .id = 3, .name = "Skoda", .price = 9000 },
    .{ .id = 4, .name = "Volvo", .price = 29000 },
    .{ .id = 5, .name = "Mercedes", .price = 57127 },
};

test "Connection and append data" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

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
}

test "Fetch data: row.scan(.{...})" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

    var result = try conn.exec("SELECT * FROM Cars", .{});
    defer result.deinit();

    var rows = result.rows(ally);
    defer rows.deinit();

    var idx: usize = 0;
    while (rows.next()) |row| : (idx += 1) {
        var id: u8 = undefined;
        var price: usize = undefined;
        var name: []const u8 = undefined;

        try row.scan(.{ &id, &name, &price });

        const res_car = corrent_result[idx];
        try std.testing.expect(res_car.id == id);
        try std.testing.expect(res_car.price == price);
        try std.testing.expect(std.mem.eql(u8, res_car.name, name));
    }
}

test "Prepare query" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

    const n_params = 0;
    const stmt = "select all cars";
    const query = "SELECT * FROM cars";

    try conn.prepare(stmt, query, n_params);

    var res = try conn.execPrepared(stmt, &.{});
    defer res.deinit();

    try std.testing.expect(res.nCols() == N_COLS);
    try std.testing.expect(res.nRows() == N_ROWS);
}
