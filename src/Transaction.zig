const std = @import("std");
const Connection = @import("Connection.zig");
const Result = @import("Result.zig");

pub const Transaction = @This();

conn: *Connection,

pub const Status = enum {};

pub fn commit(tx: *Transaction) !void {
    try tx.conn.commit();
}

pub fn rollBack(tx: *Transaction) !void {
    try tx.conn.rollBack();
}

pub fn exec(tx: *Transaction, command: []const u8, command_args: anytype) !Result {
    errdefer tx.rollBack() catch unreachable;
    return try tx.conn.execBin(command, command_args);
}

pub fn run(tx: *Transaction, command: []const u8, command_args: anytype) !void {
    errdefer tx.rollBack() catch unreachable;
    var res = try tx.conn.execBin(command, command_args);
    res.deinit();
}
