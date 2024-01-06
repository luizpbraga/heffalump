const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Result = @import("Result.zig");

pub const Rows = @This();
/// DO NOT USE THIS POINTER
res: *Result,
/// DO NOT MODIFY THIS FIELD
max_row_number: usize,
/// DO NOT MODIFY THIS FIELD
max_col_number: usize,
/// DO NOT MODIFY THIS FIELD
current_row: usize = 0,
arena: std.heap.ArenaAllocator,

/// iterate over the rows
pub fn next(rows: *Rows) ?Row {
    if (rows.current_row >= rows.max_row_number) {
        return null;
    }

    defer rows.current_row += 1;
    return .{ .info = rows.* };
}

pub fn rollBack(rows: *Rows) void {
    rows.current_row = 0;
}

pub const Row = struct {
    info: Rows,

    /// iterate over the row; allocate memory ONLY for json objects
    pub fn scan(row: *const Row, args: anytype) !void {
        if (args.len != row.info.max_col_number) return error.MissingArguments;

        inline for (0..args.len) |col_idx| {
            const value = row.info.res.getValue(row.info.current_row, col_idx).?;
            const T = @TypeOf(args[col_idx].*);
            // const oid = c.PQftype(row.info.res.pq_res, @intCast(col_idx));
            // std.debug.print("type: {} {}\n", .{ T, @as(Oid, @enumFromInt(oid)) });

            const parsed_value: T = switch (T) {
                usize, u8, u32, u16, u64, u128 => try std.fmt.parseUnsigned(T, value, 10),
                isize, i8, i32, i16, i64, i128 => try std.fmt.parseInt(T, value, 10),
                f16, f32, f64, f128 => try std.fmt.parseFloat(T, value),
                bool => if (std.mem.eql(u8, value, "true"))
                    true
                else if (std.mem.eql(u8, value, "false"))
                    false
                else
                    return error.InvalidBooleanFormat,
                []const u8, []u8 => value,
                else => v: {
                    if (@typeInfo(T) != .Struct) {
                        return error.ExpectStruct;
                    }
                    const alloc = row.info.arena.allocator();
                    break :v try std.json.parseFromSliceLeaky(T, alloc, value, .{});
                },
            };

            args[col_idx].* = parsed_value;
        }
    }

    pub fn parse(row: *const Row, comptime T: type) !T {
        var t: T = undefined;
        const fields = std.meta.fields(T);
        inline for (fields) |field| {
            const name = field.name;
            const col = row.info.res.colNumber(name) orelse 0;
            const value = row.info.res.getValue(row.info.current_row, col).?;
            @field(t, name) = value;
        }
        return t;
    }
};
