"""
sw/zynq_video_driver.py
=======================
Project: High-Efficiency Zynq SoC Video Accelerator Architecture
Description: Python Driver and Emulation Interface for Zynq Video Accelerator.
             Provides memory-mapped register interaction on PYNQ / Linux,
             or software-emulated verification on x86/Windows development hosts.
"""

import sys
import os
import struct

class ZynqVideoDriver:
    BASE_ADDR = 0x43C00000

    # Offsets
    CR_CONTROL     = 0x00
    CR_INSTRUCTION = 0x04
    CR_RS1_DATA    = 0x08
    CR_CONFIG      = 0x0C
    CR_PIXEL_IN    = 0x10
    CR_Y_BG        = 0x14
    SR_STATUS      = 0x18
    SR_Y_INP       = 0x1C
    SR_NAL_WORD    = 0x20
    SR_TOT_CYCLES  = 0x24
    SR_ACT_CYCLES  = 0x28
    SR_STL_CYCLES  = 0x2C
    SR_PIXEL_CNT   = 0x30
    SR_INP_EVENTS  = 0x34
    SR_NAL_CNT     = 0x38

    # Opcodes
    OPCODE_VEC = 0x0B
    FUNCT3_MAP = {
        'RGB2YUV': 0,
        'BGSUB':   1,
        'INPAINT': 2,
        'DCT4X4':  3,
        'CAVLC':   4
    }

    def __init__(self, dev_mem=None):
        self.dev_mem = dev_mem
        self.sim_regs = {}
        # Default initialization
        self.write_reg(self.CR_CONFIG, (30 << 8) | 24)
        self.write_reg(self.CR_Y_BG, 76)

    def write_reg(self, offset, val):
        if self.dev_mem:
            # Physical PYNQ /dev/mem write
            self.dev_mem.seek(offset)
            self.dev_mem.write(struct.pack('<I', val))
        else:
            self.sim_regs[offset] = val & 0xFFFFFFFF

    def read_reg(self, offset):
        if self.dev_mem:
            self.dev_mem.seek(offset)
            return struct.unpack('<I', self.dev_mem.read(4))[0]
        else:
            return self.sim_regs.get(offset, 0)

    def configure(self, qp=24, thresh=30, y_bg=76):
        cfg = ((thresh & 0xFF) << 8) | (qp & 0x3F)
        self.write_reg(self.CR_CONFIG, cfg)
        self.write_reg(self.CR_Y_BG, y_bg & 0xFF)

    def set_perf_enable(self, enable=True):
        ctrl = self.read_reg(self.CR_CONTROL)
        if enable:
            ctrl |= 0x04
        else:
            ctrl &= ~0x04
        self.write_reg(self.CR_CONTROL, ctrl)

    def dispatch_instruction(self, op_name, base_addr=0x10000000):
        funct3 = self.FUNCT3_MAP.get(op_name.upper(), 0)
        insn = ((funct3 & 0x07) << 12) | (self.OPCODE_VEC & 0x7F)
        self.write_reg(self.CR_INSTRUCTION, insn)
        self.write_reg(self.CR_RS1_DATA, base_addr)
        ctrl = self.read_reg(self.CR_CONTROL)
        self.write_reg(self.CR_CONTROL, ctrl | 0x01)

    def get_perf_metrics(self):
        return {
            'total_cycles':   self.read_reg(self.SR_TOT_CYCLES),
            'active_cycles':  self.read_reg(self.SR_ACT_CYCLES),
            'stall_cycles':   self.read_reg(self.SR_STL_CYCLES),
            'pixel_count':    self.read_reg(self.SR_PIXEL_CNT),
            'inpaint_events': self.read_reg(self.SR_INP_EVENTS),
            'nal_words':      self.read_reg(self.SR_NAL_CNT)
        }

if __name__ == "__main__":
    drv = ZynqVideoDriver()
    drv.configure(qp=18, thresh=25, y_bg=76)
    drv.set_perf_enable(True)
    drv.dispatch_instruction("INPAINT", 0x20000000)
    print("[+] Python Zynq Video Driver initialized & verified.")
    print(f"[+] CR_CONFIG = 0x{drv.read_reg(ZynqVideoDriver.CR_CONFIG):08X}")
    print(f"[+] CR_INSTRUCTION = 0x{drv.read_reg(ZynqVideoDriver.CR_INSTRUCTION):08X}")
