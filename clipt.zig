const std = @import("std");

const windows = std.os.windows;
const HGLOBAL = *anyopaque;

const CF_UNICODETEXT: u32 = 13;
const GMEM_MOVEABLE: u32 = 0x0002;
const ERROR_BROKEN_PIPE: u32 = 109;

extern "user32" fn OpenClipboard(owner: ?windows.HWND) callconv(.winapi) windows.BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) windows.BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) windows.BOOL;
extern "user32" fn SetClipboardData(format: u32, data: ?HGLOBAL) callconv(.winapi) ?HGLOBAL;
extern "kernel32" fn GlobalAlloc(flags: u32, bytes: usize) callconv(.winapi) ?HGLOBAL;
extern "kernel32" fn GlobalLock(memory: HGLOBAL) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(memory: HGLOBAL) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetStdHandle(which: u32) callconv(.winapi) windows.HANDLE;
extern "kernel32" fn ReadFile(handle: windows.HANDLE, buffer: [*]u8, bytes: u32, read: *u32, overlapped: ?*anyopaque) callconv(.winapi) windows.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
extern "kernel32" fn GetConsoleOutputCP() callconv(.winapi) u32;
extern "kernel32" fn GetOEMCP() callconv(.winapi) u32;
extern "kernel32" fn MultiByteToWideChar(code_page: u32, flags: u32, input: [*]const u8, input_len: c_int, output: ?[*]u16, output_len: c_int) callconv(.winapi) c_int;

fn fail(message: []const u8) noreturn {
    std.debug.print("clipt: {s}\n", .{message});
    std.process.exit(1);
}

fn decodeInput(allocator: std.mem.Allocator, input: []const u8) ![]u16 {
    if (std.unicode.utf8ValidateSlice(input)) {
        return std.unicode.utf8ToUtf16LeAlloc(allocator, input);
    }

    var code_page = GetConsoleOutputCP();
    if (code_page == 0 or code_page == 65001) code_page = GetOEMCP();
    const input_len: c_int = std.math.cast(c_int, input.len) orelse fail("input is too large");
    const output_len = MultiByteToWideChar(code_page, 0, input.ptr, input_len, null, 0);
    if (output_len == 0 and input.len != 0) fail("MultiByteToWideChar failed");

    const output = try allocator.alloc(u16, @intCast(output_len));
    errdefer allocator.free(output);
    if (output_len != 0 and MultiByteToWideChar(code_page, 0, input.ptr, input_len, output.ptr, output_len) == 0) {
        fail("MultiByteToWideChar failed");
    }
    return output;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var input_buffer = std.array_list.Managed(u8).init(allocator);
    defer input_buffer.deinit();
    const stdin = GetStdHandle(0xfffffff6);
    var chunk: [8192]u8 = undefined;
    while (true) {
        var count: u32 = 0;
        if (!ReadFile(stdin, &chunk, chunk.len, &count, null).toBool()) {
            if (GetLastError() == ERROR_BROKEN_PIPE) break;
            fail("ReadFile failed");
        }
        if (count == 0) break;
        try input_buffer.appendSlice(chunk[0..count]);
    }
    const input = try input_buffer.toOwnedSlice();
    defer allocator.free(input);

    const trimmed = std.mem.trim(u8, input, " \t\n\x0b\x0c\r");
    const decoded = try decodeInput(allocator, trimmed);
    defer allocator.free(decoded);

    const bytes = (decoded.len + 1) * @sizeOf(u16);
    const handle = GlobalAlloc(GMEM_MOVEABLE, bytes) orelse fail("GlobalAlloc failed");
    const locked = GlobalLock(handle) orelse fail("GlobalLock failed");
    const destination = @as([*]u16, @ptrCast(@alignCast(locked)))[0 .. decoded.len + 1];
    @memcpy(destination[0..decoded.len], decoded);
    destination[decoded.len] = 0;
    _ = GlobalUnlock(handle);

    if (!OpenClipboard(null).toBool()) fail("OpenClipboard failed");
    defer _ = CloseClipboard();
    if (!EmptyClipboard().toBool()) fail("EmptyClipboard failed");
    if (SetClipboardData(CF_UNICODETEXT, handle) == null) fail("SetClipboardData failed");
}
