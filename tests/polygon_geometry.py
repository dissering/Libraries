"""Run exact proposed Lua with system Lua 5.4 via ctypes; no pip dependencies.

Usage: python3 tests/polygon_geometry.py
Requires a system liblua5.4 shared library. Not a Luau compiler or renderer.
"""
import ctypes
import ctypes.util
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "Drawing.luau").read_text()
start = source.index("-- BEGIN POLYGON RASTERIZER")
end = source.index("-- END POLYGON RASTERIZER", start)
lib = ctypes.CDLL(ctypes.util.find_library("lua5.4") or "liblua5.4.so.0")
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lib.luaL_loadstring.restype = ctypes.c_int
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                         ctypes.c_longlong, ctypes.c_void_p]
lib.lua_pcallk.restype = ctypes.c_int
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]

def run(code):
    state = lib.luaL_newstate()
    try:
        lib.luaL_openlibs(state)
        status = lib.luaL_loadstring(state, code.encode())
        if not status:
            status = lib.lua_pcallk(state, 0, 0, 0, 0, None)
        if status:
            raise RuntimeError(lib.lua_tolstring(state, -1, None).decode())
    finally:
        lib.lua_close(state)

run(source[start:end] + "\n" + (root / "tests/polygon_geometry.lua").read_text())
# Lua long-string delimiter chosen to avoid collisions with the inspected source.
assert "]====]" not in source
run("local DRAWING_SOURCE = [====[" + source + "]====]\n"
    + (root / "tests/polygon_mock.lua").read_text())
