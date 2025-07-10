const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const windows = std.os.windows;
const WINAPI = windows.WINAPI;

// Windows API functions
extern "user32" fn OpenClipboard(hWndNewOwner: ?windows.HWND) callconv(WINAPI) windows.BOOL;
extern "user32" fn CloseClipboard() callconv(WINAPI) windows.BOOL;
extern "user32" fn EmptyClipboard() callconv(WINAPI) windows.BOOL;
extern "user32" fn SetClipboardData(uFormat: windows.UINT, hMem: windows.HANDLE) callconv(WINAPI) ?windows.HANDLE;
extern "kernel32" fn GlobalAlloc(uFlags: windows.UINT, dwBytes: windows.SIZE_T) callconv(WINAPI) ?windows.HANDLE;
extern "kernel32" fn GlobalLock(hMem: windows.HANDLE) callconv(WINAPI) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: windows.HANDLE) callconv(WINAPI) windows.BOOL;

const CF_TEXT = 1;
const GMEM_MOVEABLE = 0x0002;

fn setClipboardText(text: []const u8) !void {
    // Open clipboard
    if (OpenClipboard(null) == 0) {
        return error.CannotOpenClipboard;
    }
    defer _ = CloseClipboard();

    // Empty clipboard
    if (EmptyClipboard() == 0) {
        return error.CannotEmptyClipboard;
    }

    // Allocate global memory for the text (including null terminator)
    const hMem = GlobalAlloc(GMEM_MOVEABLE, text.len + 1) orelse {
        return error.CannotAllocateMemory;
    };

    // Lock the memory and copy text
    const pMem = GlobalLock(hMem) orelse {
        return error.CannotLockMemory;
    };

    const dest: [*]u8 = @ptrCast(pMem);
    @memcpy(dest[0..text.len], text);
    dest[text.len] = 0; // null terminator

    _ = GlobalUnlock(hMem);

    // Set clipboard data
    if (SetClipboardData(CF_TEXT, hMem) == null) {
        return error.CannotSetClipboardData;
    }
}

fn trimWhitespace(text: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = text.len;

    // Trim from start
    while (start < text.len and std.ascii.isWhitespace(text[start])) {
        start += 1;
    }

    // Trim from end
    while (end > start and std.ascii.isWhitespace(text[end - 1])) {
        end -= 1;
    }

    return text[start..end];
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin
    const stdin = std.io.getStdIn().reader();
    var input_buffer = ArrayList(u8).init(allocator);
    defer input_buffer.deinit();

    // Read all input
    while (true) {
        var buffer: [1024]u8 = undefined;
        const bytes_read = stdin.read(&buffer) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        
        if (bytes_read == 0) break;
        
        try input_buffer.appendSlice(buffer[0..bytes_read]);
    }

    // Trim whitespace from input
    const trimmed_text = trimWhitespace(input_buffer.items);

    // Set clipboard with trimmed text
    try setClipboardText(trimmed_text);
}
