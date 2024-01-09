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

const DSN = "user=postgres password=postgres dbname=testdb host=localhost";

test "Connection and append data" {
    var conn = try heffa.Connection.init(ally, DSN);
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

test "Transactions: rollBack" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    var tx = try conn.beginTx();
    defer tx.commit() catch unreachable;

    try tx.run(
        \\INSERT INTO cars (name, price) VALUES
        \\  ('HB20', 70000)
    , .{});

    // if some shit happened
    if (true) try conn.rollBack();
}

// exit(1) sucks!!!
// test "Transactions: Fail" {
//     var conn = try heffa.Connection.init(ally, DSN);
//     defer conn.deinit();
//
//     var tx = try conn.beginTx();
//     // defer tx.commit() catch unreachable;
//
//     try tx.run(
//         \\INSERT INTO cars (name, price) VALUES
//         \\  ('HB20', 70000)
//     , .{});
//
//     // if some shit happened, the tx is auto 'roll backed'.
//     // This mean that the command above will not be commited
//     tx.run(
//         \\INSERT INTO cars (name, price) VALUES
//         \\  ('PASSAT', 300), <= some dummy typo
//     , .{}) catch |err| {
//         try std.testing.expect(err == error.QueryFailed);
//     };
// }

test "Fetch data: row.scan(.{...})" {
    var conn = try heffa.Connection.init(ally, DSN);
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

test "Fetch data: row.get(.{...})" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    var result = try conn.exec("SELECT id, price, name FROM Cars", .{});
    defer result.deinit();

    var rows = result.rows(ally);
    defer rows.deinit();

    var idx: usize = 0;
    while (rows.next()) |row| : (idx += 1) {
        const id = try row.get(u8, "id");
        const name = try row.get([]const u8, 2);
        const price = try row.get(usize, "price");

        const res_car = corrent_result[idx];
        try std.testing.expect(res_car.id == id);
        try std.testing.expect(res_car.price == price);
        try std.testing.expect(std.mem.eql(u8, res_car.name, name));
    }
}

test "Fetch data: result.getRow(row_number)" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    var result = try conn.exec("SELECT id, price, name FROM Cars", .{});
    defer result.deinit();

    for (0..N_ROWS) |r| {
        const row = try result.getRow(r);

        const id = try row.get(u8, "id");
        const name = try row.get([]const u8, 2);
        const price = try row.get(usize, "price");

        const res_car = corrent_result[r];
        try std.testing.expect(res_car.id == id);
        try std.testing.expect(res_car.price == price);
        try std.testing.expect(std.mem.eql(u8, res_car.name, name));
    }
}

test "Prepare query" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    const n_params = 0;
    const stmt = "select all cars";
    const query = "SELECT * FROM cars";

    try conn.prepare(stmt, query, n_params);

    var res = try conn.execPrepared(stmt, .{});
    defer res.deinit();

    try std.testing.expect(res.nCols() == N_COLS);
    try std.testing.expect(res.nRows() == N_ROWS);
}

test "Update query" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    const query = "insert into cars (name, price) values ($1, $2)";
    const values = .{
        "Savero",
        "322",
    };
    var res = try conn.exec(query, values);
    defer res.deinit();
}

test "insert query: binary format" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    const query = "UPDATE cars SET price = ($1) WHERE name = ($2)";
    const values = .{
        10,
        "Savero",
    };
    var res = try conn.execBin(query, values);
    defer res.deinit();

    try conn.run("DELETE FROM cars WHERE id >= 6", .{});
}

// BUG
// test "Fetch data: row.from(.{...})" {
//     var conn = try heffa.Connection.init(ally, DSN);
//     defer conn.deinit();
//
//     var result = try conn.exec("SELECT id, price, name FROM Cars", .{});
//     defer result.deinit();
//
//     var rows = result.rows(ally);
//     defer rows.deinit();
//
//     var idx: usize = 0;
//     while (rows.next()) |row| : (idx += 1) {
//         const car = try row.from(Car);
//
//         const tcar = corrent_result[idx];
//         try std.testing.expect(tcar.id == car.id);
//         try std.testing.expect(tcar.price == car.price);
//         try std.testing.expect(std.mem.eql(u8, tcar.name, car.name));
//     }
// }
//
// test "Connection Settigns" {
//     var conn = try heffa.Connection.init2(ally, .{
//         .info = .{
//             .dbname = "testdb",
//             .password = "postgres",
//         },
//     });
//     defer conn.deinit();
// }
