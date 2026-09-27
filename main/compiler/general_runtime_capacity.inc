# General direct-native runtime ownership facts.
# Program cardinalities (inputs/bindings/states/outputs) are instance data, not
# template records.  One source-derived anonymous arena owns all mutable program
# storage; the generated read-only trailer owns type metadata and native code.

# Single runtime-arena address authority. Size is patched per AOT image from
# represented structure and actual fpP workspace demand. The address is an ABI
# locator, not a cardinality limit.
.equ GENERAL_RUNTIME_DYNAMIC_ARENA_VA,0x0000010000000000
