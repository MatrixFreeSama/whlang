# Wheelchair ShapeFact-N semantic authority.
# ShapeFact describes logical space only.  It never owns scheduling, SIMD,
# threads or solver policy.  Consumers may collapse the complete logical shape
# onto one physical execution root.
#
# Sparse axis fact:
#   axis identity
#   extent kind + payload (runtime source identity or static cardinality)
#   derived stride fact
# No rank, axis or extent-count capacity is defined here.
.equ SHAPEFN_EXTENT_STATIC,0
.equ SHAPEFN_EXTENT_RUNTIME,1
.equ SHAPEFN_Q_NAME_LEN,9
.equ SHAPEFN_PRODUCT_NAME_LEN,15
