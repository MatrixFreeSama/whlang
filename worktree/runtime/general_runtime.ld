ENTRY(_start)
PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}
SECTIONS
{
  . = 0x400000 + SIZEOF_HEADERS;
  .text : { *(.text*) } :text
  . = ALIGN(0x1000);
  .data : { *(.data*) *(.rodata*) } :data
  . = ALIGN(0x1000);
  .bss (NOLOAD) : { *(.bss*) *(COMMON) } :data
}
