from pathlib import Path

p=Path('experiments/paper_1_3_127/run_field_strict_reference.py')
s=p.read_text(encoding='utf-8')
s=s.replace("s=re.sub(r'uint32_t b;memcpy\\(&b,&sum,4\\);printf\\(\"checksum_f32_bits=0x%08x\\\\n\",b\\);',\n             'printf(\"reference_f64=%.17g\\\\n\",sum);',s)",
'''s=re.sub(r'uint32_t b;memcpy\\(&b,&sum,4\\);printf\\(\"checksum_f32_bits=0x%08x\\\\n\",b\\);',
             lambda _: 'printf(\"reference_f64=%.17g\\\\n\",sum);',s)''')
s=s.replace("s=re.sub(r'uint32_t bits; memcpy\\(&bits,&sum,4\\);\\s*printf\\(\"checksum_f32_bits=0x%08x\\\\n\",bits\\);',\n             'printf(\"reference_f64=%.17g\\\\n\",sum);',s)",
'''s=re.sub(r'uint32_t bits; memcpy\\(&bits,&sum,4\\);\\s*printf\\(\"checksum_f32_bits=0x%08x\\\\n\",bits\\);',
             lambda _: 'printf(\"reference_f64=%.17g\\\\n\",sum);',s)''')
p.write_text(s,encoding='utf-8')
