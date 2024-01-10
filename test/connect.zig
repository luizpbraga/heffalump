const std = @import("std");
const heffa = @import("heffalump");
const ally = std.testing.allocator;

test "Info.parse" {
    const info = heffa.Connection.Info{};
    try std.testing.expect(std.mem.eql(u8, "password=postgres dbname=testdb user=postgres host=localhost port=5432", info.parse()));
}

test "Connection Settigns" {
    var conn = try heffa.Connection.init2(ally, .{
        .info = .{
            .dbname = "testdb",
            .password = "postgres",
        },
    });
    defer conn.deinit();
}
