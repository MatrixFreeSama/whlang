ENTRY(gp_slot_base)
SECTIONS
{
  . = 0;
  .text : { *(.text*) }
  /DISCARD/ : { *(.note*) *(.comment*) *(.eh_frame*) }
}
