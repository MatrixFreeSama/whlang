# Wheelchair native-field external-format authority.
#
# Field and access cardinality are instance data as of 1.3.56 and therefore do
# not have compile-time capacity constants.  Rank remains the fixed width of the
# current WHFLD216 file header (extents/strides) and its rank-specialized helpers.
.equ FIELD_RUNTIME_RANK_CAP,8
