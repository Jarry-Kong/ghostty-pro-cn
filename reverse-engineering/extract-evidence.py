#!/usr/bin/env python3
"""只读解析原包的 Mach-O 字段反射与 UTF-8 字符串，输出可复查证据。"""
import json
import re
import struct
from pathlib import Path

root = Path(__file__).resolve().parent
binary = root.parent / "Ghostty Pro 中文版 1.6.0 修复版.app/Contents/MacOS/ghostty"
if not binary.exists():
    candidates = list(binary.parent.glob("*"))
    binary = next(p for p in candidates if p.is_file())
data = binary.read_bytes()
if struct.unpack_from("<I", data)[0] != 0xFEEDFACF:
    raise ValueError("仅支持当前原包的 64 位小端 Mach-O")
ncmds = struct.unpack_from("<I", data, 16)[0]
sections = []
cursor = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from("<II", data, cursor)
    if cmd == 0x19:
        count = struct.unpack_from("<I", data, cursor + 64)[0]
        for index in range(count):
            pos = cursor + 72 + index * 80
            name = data[pos:pos + 16].split(b"\0")[0].decode()
            address, length, offset = struct.unpack_from("<QQI", data, pos + 32)
            sections.append((name, address, length, offset))
    cursor += size

def offset_for(address):
    for _, start, length, offset in sections:
        if start <= address < start + length:
            return offset + address - start
    raise ValueError(f"未映射地址 {address:x}")

def relative(address):
    return address + struct.unpack_from("<i", data, offset_for(address))[0]

def string_at(address):
    offset = offset_for(address)
    end = data.index(b"\0", offset)
    return data[offset:end].decode("utf-8", errors="backslashreplace")

symbols = (root / "evidence/symbols-demangled.txt").read_text()
fields = []
for line in symbols.splitlines():
    if "reflection metadata field descriptor Ghostty." not in line:
        continue
    address = int(line.split()[0], 16)
    name = line.split("reflection metadata field descriptor ", 1)[1]
    if not any(key in name for key in ("Session", "Voice", "Speech", "Qwen", "ScriptRewriter")):
        continue
    pos = offset_for(address)
    _, record_size, count = struct.unpack_from("<HHI", data, pos + 8)
    entries = []
    for index in range(count):
        record = address + 16 + record_size * index
        entries.append({"name": string_at(relative(record + 8)),
                        "type_mangled": string_at(relative(record + 4))
                        if struct.unpack_from("<i", data, offset_for(record + 4))[0] else None})
    fields.append({"name": name, "address": hex(address), "fields": entries})
(root / "evidence/model-fields.json").write_text(json.dumps(fields, ensure_ascii=False, indent=2) + "\n")

strings = []
for name, _, length, offset in sections:
    if name != "__cstring":
        continue
    for chunk in data[offset:offset + length].split(b"\0"):
        try:
            value = chunk.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if len(value) >= 3:
            strings.append(value)
(root / "evidence/strings-utf8.txt").write_text("\n".join(strings) + "\n")
paths = sorted(set(re.findall(r"/Users/[^\n\0]*?\.swift", symbols + "\n" + "\n".join(strings))))
(root / "evidence/source-paths.txt").write_text("\n".join(paths) + "\n")
print(f"字段描述 {len(fields)} 项，UTF-8 字符串 {len(strings)} 项，源路径 {len(paths)} 项")
