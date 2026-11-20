/* ==============================================================================
 * Linker Script for PicoRV32 Supervisory Firmware (ZedBoard H.264 Encoder)
 * Memory: 32 KB internal synchronous BRAM (8192 words x 32-bit)
 * Reset vector: 0x00000000
 * Stack pointer: 0x00007FFC
 * ============================================================================== */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 32K
}

SECTIONS
{
    .text 0x00000000 : {
        . = ALIGN(4);
        *(.text.start)
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.srodata)
        *(.srodata.*)
        . = ALIGN(4);
        _etext = .;
    } > RAM

    .data : {
        . = ALIGN(4);
        _sdata = .;
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        . = ALIGN(4);
        _edata = .;
    } > RAM

    .bss : {
        . = ALIGN(4);
        _sbss = .;
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > RAM

    . = ALIGN(4);
    _end = .;

    /DISCARD/ : {
        *(.note.gnu.build-id)
        *(.comment)
        *(.riscv.attributes)
    }
}
