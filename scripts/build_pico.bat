@echo off
set GCC=C:\AMDDesignTools\2026.1\gnu\riscv\nt\bin\riscv64-unknown-elf-gcc.exe
set OBJCOPY=C:\AMDDesignTools\2026.1\gnu\riscv\nt\bin\riscv64-unknown-elf-objcopy.exe
set LIBGCC=C:\AMDDesignTools\2026.1\gnu\riscv\nt\riscv32-xilinx-elf\usr\lib\rv32i\ilp32\riscv32-xilinxmllibrv32i-elf\13.4.0\libgcc.a

"%GCC%" -march=rv32i -mabi=ilp32 -Os -nostdlib -Wl,-T,pico.ld,--build-id=none -o pico_fw.elf pico_start.S pico_main.c "%LIBGCC%"
if errorlevel 1 exit /b 1

"%OBJCOPY%" -O binary pico_fw.elf pico_fw.bin
if errorlevel 1 exit /b 1

python scripts\firmware_to_mem.py pico_fw.bin pico_fw.mem
if errorlevel 1 exit /b 1

echo Pico firmware build complete.

