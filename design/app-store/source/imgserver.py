# Minimal RFB 3.8 server for App Store screenshots. Sends desktop.rgbx, the mock Mac desktop, as the screen.
import socket, struct, threading, sys

W, H = 2560, 1600
import os
RGBX = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'desktop.rgbx'), 'rb').read()
FIELD = (60, 760, 1380, 840)  # x0, y0, x1, y1 — a text box near the bottom

def pixel_rgb(x, y):
    x0, y0, x1, y1 = FIELD
    if x0 <= x < x1 and y0 <= y < y1:
        if x in (x0, x1 - 1) or y in (y0, y1 - 1): return (40, 120, 255)
        return (255, 255, 255)
    if y < 60: return (225, 225, 230)
    if 200 <= y < 260 and 500 <= x < 940: return (60, 60, 70)  # a "heading"
    return (246, 245, 242)

def build_frame(fmt):
    # The image is stored as R, G, B, X bytes. Reorder to the client's 32-bit true-colour format.
    bpp, depth, big, true, rmax, gmax, bmax, rs, gs, bs = fmt
    src = memoryview(RGBX); out = bytearray(len(RGBX))
    pos = {rs // 8: 0, gs // 8: 1, bs // 8: 2}
    for byte_index in range(4):
        dst = 3 - byte_index if big else byte_index
        if byte_index in pos: out[dst::4] = src[pos[byte_index]::4]
    return bytes(out)

def cursor_rect(kind, fmt):
    bpp, depth, big, true, rmax, gmax, bmax, rs, gs, bs = fmt
    if kind == 'ibeam':
        w, h, hx, hy = 24, 18, 12, 9
        on = lambda x, y: x == 12 or ((y in (0, h - 1)) and 9 <= x <= 15)
    else:
        w, h, hx, hy = 12, 19, 1, 1
        on = lambda x, y: x <= y * 0.6 and y < 17
    px = b''.join(struct.pack('>I' if big else '<I', 0) for y in range(h) for x in range(w))
    mask = b''
    for y in range(h):
        row = 0
        for x in range(w):
            if on(x, y): row |= 1 << (7 - x % 8) << (8 * ((w + 7) // 8 - 1 - x // 8))
        mask += row.to_bytes((w + 7) // 8, 'big')
    return struct.pack('>BxH', 0, 1) + struct.pack('>HHHHi', hx, hy, w, h, -239) + px + mask

def recv_exact(c, n):
    buf = b''
    while len(buf) < n:
        chunk = c.recv(n - len(buf))
        if not chunk: raise EOFError
        buf += chunk
    return buf

def serve(c):
    global W, H
    fmt = (32, 24, 0, 1, 255, 255, 255, 16, 8, 0)
    c.sendall(b'RFB 003.008\n'); recv_exact(c, 12)
    if len(sys.argv) > 2 and sys.argv[2] == 'auth':
        c.sendall(bytes([1, 2])); recv_exact(c, 1)      # security: VNC password
        c.sendall(bytes(16)); recv_exact(c, 16)         # challenge, response (any password works)
        print('Password received', flush=True)
    else:
        c.sendall(bytes([1, 1])); recv_exact(c, 1)      # security: None
    c.sendall(struct.pack('>I', 0))                      # SecurityResult OK
    recv_exact(c, 1)                                     # ClientInit
    name = b'MacBook Pro'
    c.sendall(struct.pack('>HHBBBBHHHBBB3x', W, H, *fmt) + struct.pack('>I', len(name)) + name)
    frame = None
    wants_cursor = False
    shape = None
    while True:
        t = recv_exact(c, 1)[0]
        if t == 0:
            d = recv_exact(c, 19)
            fmt = struct.unpack('>BBBBHHHBBB', d[3:16]); frame = None
            print('SetPixelFormat', fmt, flush=True)
        elif t == 2:
            _, n = struct.unpack('>BH', recv_exact(c, 3))
            encodings = struct.unpack('>%di' % n, recv_exact(c, 4 * n))
            wants_cursor = -239 in encodings
        elif t == 3:
            recv_exact(c, 9)
            if frame is None:
                frame = build_frame(fmt)
                c.sendall(struct.pack('>BxH', 0, 1) + struct.pack('>HHHHi', 0, 0, W, H, 0) + frame)
        elif t == 4:
            down, key = struct.unpack('>B2xI', recv_exact(c, 7))
            print(f'Key {"down" if down else "up"} {hex(key)}', flush=True)
            if down and key == ord('r'):
                W, H = (1920, 1080) if W == 1440 else (1440, 900)
                c.sendall(struct.pack('>BxH', 0, 1) + struct.pack('>HHHHi', 0, 0, W, H, -223))
                frame = None
                print(f'Resized to {W}x{H}', flush=True)
        elif t == 5:
            mask, x, y = struct.unpack('>BHH', recv_exact(c, 5))
            if mask: print(f'Pointer buttons={mask} at {x},{y}', flush=True)
            x0, y0, x1, y1 = FIELD
            new_shape = 'ibeam' if x0 <= x < x1 and y0 <= y < y1 else 'arrow'
            if wants_cursor and new_shape != shape:
                shape = new_shape
                c.sendall(cursor_rect(shape, fmt))
                print('Cursor', shape, flush=True)
        elif t == 6:
            recv_exact(c, 3); n = struct.unpack('>I', recv_exact(c, 4))[0]; recv_exact(c, n)
        else:
            print('Unknown message', t, flush=True); return

s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', int(sys.argv[1]))); s.listen()
print('listening', flush=True)
while True:
    conn, _ = s.accept()
    threading.Thread(target=lambda: (lambda c: (serve(c) if True else None))(conn), daemon=True).start()
