/* ==============================================================================
 * Assembly Startup for PicoRV32 (ZedBoard H.264 Encoder)
 * Standard: RV32I
 * ============================================================================== */

.section .text.start
.global _start
.type _start, @function

_start:
    /* Set stack pointer to top of 32 KB BRAM (0x00007FFC) */
    li sp, 0x00007FFC

    /* Initialize Global Pointer (gp) to 0 */
    li gp, 0

    /* Zero out the .bss section */
    la a0, _sbss
    la a1, _ebss
bss_clear_loop:
    bge a0, a1, bss_clear_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_clear_loop
bss_clear_done:

    /* Call C entry point */
    call main

    /* Trap loop if main ever returns */
trap_loop:
    j trap_loop

.size _start, . - _start

