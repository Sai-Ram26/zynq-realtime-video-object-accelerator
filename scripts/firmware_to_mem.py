#!/usr/bin/env python3
"""
firmware_to_mem.py
Convert a RISC-V raw binary (.bin) file into a 32-bit hexadecimal ($readmemh) memory file (.mem).
Default memory size: 8192 words (32 KB), little-endian word layout.
"""

import sys
import struct

def bin_to_mem(bin_path, mem_path, total_words=8192):
    with open(bin_path, "rb") as f:
        data = f.read()

    # Pad data to 4-byte multiple
    remainder = len(data) % 4
    if remainder != 0:
        data += b'\x00' * (4 - remainder)

    words = []
    for i in range(0, len(data), 4):
        # Little-endian 32-bit word unpack
        val = struct.unpack("<I", data[i:i+4])[0]
        words.append(val)

    if len(words) > total_words:
        raise ValueError(f"Firmware binary size ({len(words)} words) exceeds memory size ({total_words} words / {total_words*4} bytes)!")

    # Pad with zeros up to total_words
    while len(words) < total_words:
        words.append(0)

    with open(mem_path, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")

    print(f"Successfully converted {bin_path} -> {mem_path} ({len(data)} code/data bytes, {total_words} words padded).")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python firmware_to_mem.py <input.bin> <output.mem> [total_words]")
        sys.exit(1)

    bin_file = sys.argv[1]
    mem_file = sys.argv[2]
    words = int(sys.argv[3]) if len(sys.argv) > 3 else 8192
    bin_to_mem(bin_file, mem_file, words)

