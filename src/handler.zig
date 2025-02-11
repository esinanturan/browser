// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

const ws = @import("websocket");
const Msg = @import("msg.zig").Msg;

const log = std.log.scoped(.handler);

pub const Stream = struct {
    addr: std.net.Address,
    socket: std.posix.socket_t = undefined,

    ws_host: []const u8,
    ws_port: u16,
    ws_conn: *ws.Conn = undefined,

    fn connectCDP(self: *Stream) !void {
        const flags: u32 = std.posix.SOCK.STREAM;
        const proto = blk: {
            if (self.addr.any.family == std.posix.AF.UNIX) break :blk @as(u32, 0);
            break :blk std.posix.IPPROTO.TCP;
        };
        const socket = try std.posix.socket(self.addr.any.family, flags, proto);

        try std.posix.connect(
            socket,
            &self.addr.any,
            self.addr.getOsSockLen(),
        );
        log.debug("connected to Stream server", .{});
        self.socket = socket;
    }

    fn closeCDP(self: *const Stream) void {
        const close_msg: []const u8 = .{ 5, 0, 0, 0 } ++ "close";
        self.recv(close_msg) catch |err| {
            log.err("stream close error: {any}", .{err});
        };
        std.posix.close(self.socket);
    }

    fn start(self: *Stream, ws_conn: *ws.Conn) !void {
        try self.connectCDP();
        self.ws_conn = ws_conn;
    }

    pub fn recv(self: *const Stream, data: []const u8) !void {
        var pos: usize = 0;
        while (pos < data.len) {
            const len = try std.posix.write(self.socket, data[pos..]);
            pos += len;
        }
    }

    pub fn send(self: *const Stream, data: []const u8) !void {
        return self.ws_conn.write(data);
    }
};

pub const Handler = struct {
    stream: *Stream,

    pub fn init(_: ws.Handshake, ws_conn: *ws.Conn, stream: *Stream) !Handler {
        try stream.start(ws_conn);
        return .{ .stream = stream };
    }

    pub fn close(self: *Handler) void {
        self.stream.closeCDP();
    }

    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        var header: [4]u8 = undefined;
        Msg.setSize(data.len, &header);
        try self.stream.recv(&header);
        try self.stream.recv(data);
    }
};
