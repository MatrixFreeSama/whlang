ENTRY(_start)
PHDRS
{
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  generated PT_LOAD FLAGS(5);
}
SECTIONS
{
  . = 0x400000 + SIZEOF_HEADERS;
  .text : { *(.text*) } :text
  . = ALIGN(0x1000);
  .data : { *(.data*) *(.rodata*) } :data
  . = ALIGN(8);
  .bss (NOLOAD) : { *(.bss*) *(COMMON) } :data
  . = ALIGN(0x1000);
  .generated : {
    generated_base = .;
    BYTE(0);
    generated_template_end = .;
  } :generated
}
