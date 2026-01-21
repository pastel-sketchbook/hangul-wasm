//! hangul-wasm static file server
//!
//! A minimal static file server using http.zig for serving the hangul-wasm demo.
//! Serves files from the parent directory (project root) on port 8120.

const std = @import("std");
const httpz = @import("httpz");

const log = std.log.scoped(.server);

/// Files allowed to be served (whitelist for security)
const allowed_files = [_][]const u8{
    "/index.html",
    "/hangul.wasm",
    "/hangul-ime.js",
    "/hangul-ime.d.ts",
    "/screenshot.png",
    "/README.md",
    "/",
};

/// MIME type mappings
const MimeType = struct {
    ext: []const u8,
    mime: []const u8,
};

const mime_types = [_]MimeType{
    .{ .ext = ".html", .mime = "text/html; charset=utf-8" },
    .{ .ext = ".js", .mime = "application/javascript; charset=utf-8" },
    .{ .ext = ".ts", .mime = "application/typescript; charset=utf-8" },
    .{ .ext = ".wasm", .mime = "application/wasm" },
    .{ .ext = ".png", .mime = "image/png" },
    .{ .ext = ".md", .mime = "text/markdown; charset=utf-8" },
    .{ .ext = ".css", .mime = "text/css; charset=utf-8" },
    .{ .ext = ".json", .mime = "application/json; charset=utf-8" },
};

fn getMimeType(path: []const u8) []const u8 {
    for (mime_types) |mt| {
        if (std.mem.endsWith(u8, path, mt.ext)) {
            return mt.mime;
        }
    }
    return "application/octet-stream";
}

fn isAllowedPath(path: []const u8) bool {
    for (allowed_files) |allowed| {
        if (std.mem.eql(u8, path, allowed)) {
            return true;
        }
    }
    return false;
}

/// Handler context - holds the root directory for serving files
const Handler = struct {
    root_dir: std.fs.Dir,

    pub fn handle(self: *Handler, req: *httpz.Request, res: *httpz.Response) void {
        self.serveFile(req, res) catch |err| {
            log.err("Error serving {s}: {}", .{ req.url.path, err });
            res.status = 500;
            res.body = "Internal Server Error";
        };
    }

    fn serveFile(self: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
        var path = req.url.path;

        // Serve index.html for root path
        if (std.mem.eql(u8, path, "/")) {
            path = "/index.html";
        }

        // Security: Only allow whitelisted files
        if (!isAllowedPath(path)) {
            log.warn("Blocked request for: {s}", .{path});
            res.status = 404;
            res.body = "Not Found";
            return;
        }

        // Remove leading slash for file system access
        const file_path = if (path.len > 0 and path[0] == '/') path[1..] else path;

        // Open and read the file
        const file = self.root_dir.openFile(file_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                log.info("File not found: {s}", .{file_path});
                res.status = 404;
                res.body = "Not Found";
                return;
            }
            return err;
        };
        defer file.close();

        const stat = try file.stat();
        const content = try res.arena.alloc(u8, stat.size);
        const bytes_read = try file.readAll(content);

        // Set response
        res.status = 200;
        res.body = content[0..bytes_read];

        // Set content type based on extension using header
        res.header("Content-Type", getMimeType(path));
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments for port
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var port: u16 = 8120;
    var root_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--port") or std.mem.eql(u8, args[i], "-p")) {
            if (i + 1 < args.len) {
                port = std.fmt.parseInt(u16, args[i + 1], 10) catch {
                    log.err("Invalid port number: {s}", .{args[i + 1]});
                    return error.InvalidPort;
                };
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--root") or std.mem.eql(u8, args[i], "-r")) {
            if (i + 1 < args.len) {
                root_path = args[i + 1];
                i += 1;
            }
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            std.debug.print(
                \\hangul-server - Static file server for hangul-wasm demo
                \\
                \\Usage: hangul-server [options]
                \\
                \\Options:
                \\  -p, --port <port>  Port to listen on (default: 8120)
                \\  -r, --root <path>  Root directory to serve files from (default: current directory)
                \\  -h, --help         Show this help message
                \\
            , .{});
            return;
        }
    }

    // Open the root directory for serving files
    var root_dir = if (root_path) |path|
        try std.fs.cwd().openDir(path, .{})
    else
        try std.fs.cwd().openDir(".", .{});
    defer root_dir.close();

    var handler = Handler{
        .root_dir = root_dir,
    };

    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = port,
        .address = "127.0.0.1",
    }, &handler);
    defer server.deinit();

    log.info("hangul-wasm demo server starting...", .{});
    log.info("Serving files on http://127.0.0.1:{d}", .{port});
    log.info("Press Ctrl+C to stop", .{});

    // Start the server (blocks)
    try server.listen();
}
