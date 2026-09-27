ENTRY(gr_release_base)
SECTIONS
{
  . = 0;
  .text : { *(.text*) }
  /DISCARD/ : { *(.note*) *(.comment*) *(.eh_frame*) }
}
