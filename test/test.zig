const std = @import("std");
const heffa = @import("heffalump");

const Car = struct {
    id: []const u8,
    name: []const u8,
    price: []const u8,
};

test "fetch data: 'row.scan'" {
    const ally = std.testing.allocator;

    var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
    // defer conn.deinit();

    //
    // let's run some queries
    //
    try conn.run("DROP TABLE IF EXISTS Cars;", .{});
    // try conn.run(
    //     \\CREATE TABLE IF NOT EXISTS Cars(
    //     \\  id      INTEGER PRIMARY KEY auto_increment,
    //     \\  name    VARCHAR(20),
    //     \\  price   INTEGER
    //     \\);
    // , .{});
    // try conn.run("INSERT INTO CARS VALUES('Gol',200)", .{});
    // try conn.run("INSERT INTO CARS VALUES('BMW',78000)", .{});
    // try conn.run("INSERT INTO CARS VALUES('Skoda',9000)", .{});
    // try conn.run("INSERT INTO CARS VALUES('Volvo',29000)", .{});
    // try conn.run("INSERT INTO CARS VALUES('Mercedes',57127)", .{});

    // var result = try conn.exec("SELECT * FROM Cars", .{});
    // defer result.deinit();
    //
    // var rows = result.rows(ally);
    // while (rows.next()) |row| {
    //     var id: u8 = undefined;
    //     var name: []const u8 = undefined;
    //     var price: usize = undefined;
    //     try row.scan(.{ &id, &name, &price });
    //
    //     std.debug.print("id: {}, name: {s}, price: {}\n", .{ id, name, price });
    // }
}
//
// // test "put data: commited transaction" {
// //     const ally = std.testing.allocator;
// //
// //     var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
// //     defer conn.deinit();
// //
// //     const count = b: {
// //         var result = try conn.exec("SELECT COUNT(*) FROM cars", .{});
// //         defer result.deinit();
// //         const value_string = result.getValue(0, 0).?;
// //         break :b try std.fmt.parseInt(usize, value_string, 10);
// //     };
// //
// //     {
// //         var result = try conn.exec("SELECT id FROM cars", .{});
// //         defer result.deinit();
// //     }
// //
// //     try std.testing.expect(count == 5);
// // }
//
// test "fetch data: 'row.parse'" {
//     const ally = std.testing.allocator;
//
//     var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
//     defer conn.deinit();
//
//     var result = try conn.exec("SELECT * FROM cars", .{});
//     defer result.deinit();
//
//     var rows = result.rows();
//     while (rows.next()) |row| {
//         const car = try row.parse(Car);
//         std.debug.print("id: {s}, name: {s}, price: {s}\n", .{ car.id, car.name, car.price });
//     }
// }
//
// test "Connection" {
//     const ally = std.testing.allocator;
//
//     var conn = try heffa.Connection.init(ally, "user=postgres password=postgres dbname=testdb host=localhost");
//     defer conn.deinit();
//
//     var result = try conn.exec("SELECT * FROM cars", .{});
//     defer result.deinit();
// }
