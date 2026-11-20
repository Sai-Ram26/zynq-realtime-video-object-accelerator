# Repository Cleanup Manifest

This manifest documents the safe cleanup of disposable clutter from the repository root `D:\mini_project2` in accordance with Phase B and Section 25 of the Model-4 Master Prompt.

## Classification Summary

| Category | Description | Action |
|---|---|---|
| **Authoritative Source** | Hand-written RTL (`h264_accel_top.sv`, `rtl/*.sv`), constraints (`zedboard.xdc`), firmware (`arm_main.c`, `pico_*.c`, `pico_fw.mem`), scripts, docs | **PRESERVED** |
| **Active Project & IP** | `vivado_build/` (`.xpr`, `.bd`, IP output products, block design, sources) | **PRESERVED** |
| **Checkpoints & Deliverables** | `RELEASE/encoder.bit`, `RELEASE/encoder.xsa`, implementation DCPs (`design_1_wrapper_routed.dcp`) | **PRESERVED** |
| **Web Dashboard** | `web/`, `dashboard/`, `server.py`, `start_dashboard.bat` | **PRESERVED** |
| **Disposable Clutter** | Stale backup logs/journals from previous GUI sessions, temporary simulator logs/directories, OS/Python caches | **DELETED** |

---

## Deleted Clutter Files

| File Path | Original Size (Bytes) | Reason & Evidence Unused |
|---|---:|---|
| `nlviewcommon.logfile` | 1,849,904 | Stale schematic view GUI session log from old Vivado run |
| `vivado_11284.backup.log` | 187,784 | Stale process backup log (PID 11284) |
| `vivado_11284.backup.jou` | 1,053 | Stale process journal (PID 11284) |
| `vivado_21252.backup.log` | 336,951 | Stale process backup log (PID 21252) |
| `vivado_21252.backup.jou` | 1,053 | Stale process journal (PID 21252) |
| `vivado_21484.backup.log` | 339,208 | Stale process backup log (PID 21484) |
| `vivado_21484.backup.jou` | 1,053 | Stale process journal (PID 21484) |
| `vivado_22404.backup.log` | 176,780 | Stale process backup log (PID 22404) |
| `vivado_22404.backup.jou` | 1,053 | Stale process journal (PID 22404) |
| `vivado_23216.backup.log` | 187,785 | Stale process backup log (PID 23216) |
| `vivado_23216.backup.jou` | 1,053 | Stale process journal (PID 23216) |
| `xsim_12524.backup.log` | 1,440 | Stale xsim backup log (PID 12524) |
| `xsim_12524.backup.jou` | 1,048 | Stale xsim journal (PID 12524) |
| `xsim_12848.backup.log` | 1,497 | Stale xsim backup log (PID 12848) |
| `xsim_12848.backup.jou` | 1,064 | Stale xsim journal (PID 12848) |
| `xsim_13228.backup.log` | 1,386 | Stale xsim backup log (PID 13228) |
| `xsim_13228.backup.jou` | 1,082 | Stale xsim journal (PID 13228) |
| `xsim_14092.backup.log` | 1,397 | Stale xsim backup log (PID 14092) |
| `xsim_14092.backup.jou` | 1,086 | Stale xsim journal (PID 14092) |
| `xsim_5396.backup.log` | 2,598 | Stale xsim backup log (PID 5396) |
| `xsim_5396.backup.jou` | 1,057 | Stale xsim journal (PID 5396) |
| `xelab.log` | 885 | Temporary compilation log |
| `xelab.pb` | 1,518 | Temporary compilation protocol buffer |
| `xvlog.log` | 538 | Temporary verilog compilation log |
| `xvlog.pb` | 764 | Temporary verilog compilation protocol buffer |
| `xsim.jou` | 1,068 | Temporary simulation journal |
| `xsim.log` | 1,353 | Temporary simulation log |
| `xsim.dir/` | Directory | Temporary simulator working cache; regenerated on demand |
| `__pycache__/` | Directory | Python bytecode cache; regenerated on demand |

**Total Space Reclaimed:** **~3.1 MB**
