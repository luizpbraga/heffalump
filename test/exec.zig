const std = @import("std");
const heffa = @import("heffalump");
const ally = std.testing.allocator;

const DSN = "user=postgres password=postgres dbname=testdb host=localhost";

// test "execBin" {
//     var conn = try heffa.Connection.init(ally, DSN);
//     defer conn.deinit();
//
//     try conn.run("DROP TABLE IF EXISTS _exec_test;", .{});
//
//     try conn.run(
//         \\CREATE TABLE IF NOT EXISTS _exec_test (
//         \\    b     bool,
//         \\
//         \\    ids   SERIAL,
//         \\    id2   int2,
//         \\    id4   int4,
//         \\    id8   int8,
//         \\
//         \\    name  VARCHAR(20),
//         \\    email TEXT,
//         \\
//         \\    price float8
//         \\)
//     , .{});
//
//     // floats are broken
//     for (1..2) |i| {
//         // bit is broken
//         // floats is broken
//         const price: f64 = @floatFromInt(i);
//         // ints
//         const ids: i32 = @intCast(i);
//         const id2: i16 = @intCast(i);
//         const id4: i32 = @intCast(i);
//         const id8: i64 = @intCast(i);
//
//         // text
//         const name = "test";
//         const email = "test";
//
//         var res = try conn.execBin(
//             \\INSERT INTO _exec_test
//             \\(b, ids, id2, id4, id8, name, email, price )
//             \\VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
//         , .{ true, ids, id2, id4, id8, name, email, price });
//         defer res.deinit();
//     }
// }

// test "execBin: json" {
//     var conn = try heffa.Connection.init(ally, DSN);
//     defer conn.deinit();
//
//     try conn.run("DROP TABLE IF EXISTS _exec_test_json;", .{});
//
//     try conn.run(
//         \\CREATE TABLE IF NOT EXISTS _exec_test_json ( j json )
//     , .{});
//
//     const j =
//         \\{"x":1}
//     ;
//
//     var res = try conn.execBin(
//         \\INSERT INTO _exec_test_json (j) VALUES ($1)
//     ,
//         .{j},
//     );
//     defer res.deinit();
// }
//
test "execBin: trick" {
    var conn = try heffa.Connection.init(ally, DSN);
    defer conn.deinit();

    try conn.run("DROP TABLE IF EXISTS _exec_test;", .{});

    try conn.run(
        \\CREATE TABLE IF NOT EXISTS _exec_test ( bs float8 )
    , .{});

    for (0..1) |i| {
        const bs: f64 = @floatFromInt(i);

        var res = try conn.execBin(
            \\INSERT INTO _exec_test (bs) VALUES ($1)
        , .{bs + 9.1});
        defer res.deinit();
    }
}
