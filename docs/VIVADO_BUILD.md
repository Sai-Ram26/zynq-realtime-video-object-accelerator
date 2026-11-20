# Vivado Build and Programming Guide

## Authoritative files

The Model-4 build uses these files from the repository root:

- `h264_accel_top.sv` - synthesizable Model-4 RTL, including the PicoRV32 implementation
- `pico_fw.mem` - firmware memory image loaded by the RTL
- `zedboard.xdc` - ZedBoard PL pin constraints
- `build_zedboard.tcl` - clean project, block design, implementation, bitstream, and XSA flow
- `fast_build.tcl` - rebuild flow for an existing `vivado_build` project
- `vivado_pre_hook.tcl` - Windows Vivado run settings

The `vivado_build` directory is generated and does not need to be kept or uploaded.

## Build from Windows Command Prompt

Open Command Prompt and run:

```cmd
cd /d D:\mini_project2
C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat -mode batch -source D:\mini_project2\build_zedboard.tcl -notrace
```

The script creates the project in `D:\mini_project2\vivado_build`, then generates:

```text
D:\mini_project2\RELEASE\encoder.bit
D:\mini_project2\RELEASE\encoder.xsa
```

The build targets a conservative 50 MHz PL clock so implementation can close timing on the Zynq-7020 device. The previous 75 MHz and 100 MHz targets generated bitstreams but did not close setup timing.

The latest verified post-route result for the current sources is:

- Setup WNS: `+0.127 ns`
- Setup failing endpoints: `0`
- Hold WNS: `+0.009 ns`
- PL clock: `50 MHz` (`20 ns` period)
- Bitstream and XSA generation: successful

The current automated checks also pass:

- PicoRV32 bring-up simulation: all 5 checks passed
- ARM/Pico mailbox simulation: all 6 checks passed
- DDR read/write engine simulation: all 5 checks passed
- Source frontend, YUV420 scaler, BRAM-backed macroblock packer, and
  source-to-tile integration simulations passed
- Routed DRC errors: `0`
- Timing violations: `0`

Vivado may still report warnings from generated AMD IP, intentionally unused
debug/monitor ports, and vectorless power analysis of reset activity. The
generated bitstream is timing-closed, but it is not a substitute for
programming and testing a physical ZedBoard.

## Build from the Vivado Tcl Console

In Vivado, select **Tools > Run Tcl Script** or use the Tcl Console:

```tcl
cd {D:\mini_project2}
source {D:\mini_project2\build_zedboard.tcl}
```

For a project that already exists:

```tcl
cd {D:\mini_project2}
source {D:\mini_project2\fast_build.tcl}
```

Use the full build after cleaning `vivado_build`, changing the block design, changing constraints, or changing project sources. Use the fast build only when `vivado_build\zedboard_video_accel.xpr` already exists.

## Program the FPGA

1. Connect the ZedBoard JTAG cable and power on the board.
2. Open Vivado Hardware Manager.
3. Select **Open Target > Auto Connect**.
4. Select the detected `xc7z020` device.
5. Right-click the device and select **Program Device**.
6. Select:

```text
D:\mini_project2\RELEASE\encoder.bit
```

The XSA is used to create or update a Vitis platform:

```text
D:\mini_project2\RELEASE\encoder.xsa
```

Vitis is not uploaded to the FPGA. Use it only when the Zynq processing-system
software is required:

1. In Vitis, create a platform project from `RELEASE\encoder.xsa`.
2. Create a standalone-domain application project for the Cortex-A9.
3. Add the ARM application source (`vitis\src\main.c`) and build the application.
4. Connect the ZedBoard by JTAG, then use **Program Device** for
   `RELEASE\encoder.bit`.
5. In Vitis, launch the application configuration on the target to download the
   generated ELF to the ARM processor.

The ARM application configures the ZedBoard Ethernet interface as
`192.168.1.50/24` and listens on TCP port `5001`. The laptop must be on the
same subnet. Start the dashboard only after the application is running; the
dashboard reports the board as connected only when this TCP service accepts a
connection.

The bitstream configures the programmable logic. The ELF runs on the Zynq ARM;
it is not part of the FPGA bitstream. If you only need to configure the
accelerator hardware, programming `encoder.bit` is sufficient.

## Optional batch launcher

The repository also contains `run_bitstream_build.bat`. It launches the same full flow and pauses after completion:

```cmd
cd /d D:\mini_project2
run_bitstream_build.bat
```

## Reproducibility and cleanup

Generated Vivado directories and logs can be removed safely:

```powershell
Remove-Item -LiteralPath D:\mini_project2\vivado_build -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath D:\mini_project2\.Xil -Recurse -Force -ErrorAction SilentlyContinue
```

Do not delete `h264_accel_top.sv`, `pico_fw.mem`, `zedboard.xdc`, or the root Tcl scripts; they are the inputs required to reproduce the build.
