const std = @import("std");
const heffa = @import("heffalump");
const ally = std.testing.allocator;

const Car = struct {
    id: []const u8,
    name: []const u8,
    price: []const u8,
};

test "fetch data: 'row.scan'" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

    try conn.run("DROP TABLE IF EXISTS Cars;", .{});
    try conn.run(
        \\CREATE TABLE IF NOT EXISTS Cars (
        \\    id SERIAL PRIMARY KEY,
        \\    nome VARCHAR(20),
        \\    price INT
        \\)
    , .{});
    try conn.run("INSERT INTO CARS (nome, price) VALUES('Gol',200)", .{});
    try conn.run("INSERT INTO CARS (nome, price) VALUES('BMW',78000)", .{});
    try conn.run("INSERT INTO CARS (nome, price) VALUES('Skoda',9000)", .{});
    try conn.run("INSERT INTO CARS (nome, price) VALUES('Volvo',29000)", .{});
    try conn.run("INSERT INTO CARS (nome, price) VALUES('Mercedes',57127)", .{});

    var result = try conn.exec("SELECT * FROM Cars", .{});
    defer result.deinit();

    var rows = result.rows(ally);
    while (rows.next()) |row| {
        var id: u8 = undefined;
        var name: []const u8 = undefined;
        var price: usize = undefined;
        try row.scan(.{ &id, &name, &price });

        std.debug.print("id: {}, name: {s}, price: {}\n", .{ id, name, price });
    }
}

test "fetch data: 'row.parse'" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

    var result = try conn.exec("SELECT * FROM cars", .{});
    defer result.deinit();

    var rows = result.rows(ally);
    while (rows.next()) |row| {
        const car = try row.parse(Car);
        std.debug.print("id: {s}, name: {s}, price: {s}\n", .{ car.id, car.name, car.price });
    }
}

test "Connection" {
    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    defer conn.deinit();

    var result = try conn.exec("SELECT * FROM cars", .{});
    defer result.deinit();
}
