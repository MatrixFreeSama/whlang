#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"1.2.2 patch rejected for {path}: expected one protected anchor, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

# WHEX: shared product physicalizer, multi-axis `each`, semantic proof attachment,
# and compile-time lane selection. Existing rank-1 data has no marker and keeps
# using build/topologyc exactly.
p = ROOT / "surface/whex_surface.py"
once(p, "import whex_semantics as ws\n", "import whex_semantics as ws\nimport rank_n_product as rnp\n")
once(p,
'''    def parse_each(self) -> None:
        # each i in n, j in m { field_name: f64 = expression }
        axes: list[dict[str, Any]] = []; names: set[str] = set()
        axis = self.parse_name(allow_numeric=True)
        self.expect_kw("in"); extent = self.parse_expr()
        axes.append({"name": axis, "extent": extent}); names.add(axis)
        if self.match_op(","):
            raise self.error("current dedicated topologyc currently accepts exactly one explicit topology axis")
        self.expect_op("{")
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":"); typ = self.parse_scalar_type()
        if typ != "f64": raise self.error("current dedicated topologyc WHEX fields are currently f64")
        if axes[0].get("extent") != {"var":"n"}: raise self.error("current dedicated topologyc WHEX each extent must be n")
        self.expect_op("=")
        self.axes.append(names)
        try: expr = self.parse_expr()
        finally: self.axes.pop()
        self.optional_semicolon(); self.expect_op("}"); self.optional_semicolon()
        self.data["bindings"].append({"name": name, "op": "map", "type": typ, "axes": axes, "expr": expr})
        self.binding_regions.setdefault(name, self.current_region)
''',
'''    def parse_each(self) -> None:
        # Familiar block form of a structural Rank-N map. No axis is serialized.
        axes: list[dict[str, Any]] = []; names: set[str] = set()
        while True:
            axis = self.parse_name(allow_numeric=True)
            if axis in names: raise self.error(f"duplicate topology axis {axis!r}")
            self.expect_kw("in"); extent = self.parse_expr()
            axes.append({"name": axis, "extent": extent}); names.add(axis)
            if self.match_op(","): continue
            break
        self.expect_op("{")
        name = self.parse_name(allow_numeric=True)
        self.expect_op(":"); typ = self.parse_scalar_type()
        if typ != "f64": raise self.error("current dedicated topologyc WHEX fields are currently f64")
        if len(axes)==1 and axes[0].get("extent") != {"var":"n"}: raise self.error("current native topologyc WHEX rank-1 each extent must be n")
        self.expect_op("=")
        self.axes.append(names)
        try: expr = self.parse_expr()
        finally: self.axes.pop()
        self.optional_semicolon(); self.expect_op("}"); self.optional_semicolon()
        self.data["bindings"].append({"name": name, "op": "map", "type": typ, "axes": axes, "expr": expr})
        self.binding_regions.setdefault(name, self.current_region)
''')
once(p,
'''        self.semantic_plan = ws.build_plan(
            self.data, functions=self.functions, records=self.records,
            axis_declarations=self.axis_declarations,
            binding_regions=self.binding_regions, regions=self.regions,
            rank_n_erasures=self.rank_n_erasures,
        )
        return self.data
''',
'''        plan = ws.build_plan(
            self.data, functions=self.functions, records=self.records,
            axis_declarations=self.axis_declarations,
            binding_regions=self.binding_regions, regions=self.regions,
            rank_n_erasures=self.rank_n_erasures,
        )
        try:
            physical, evidence = rnp.physicalize(self.data)
        except rnp.RankNPhysicalizationError as exc:
            raise wh.SurfaceError(str(exc)) from exc
        if evidence:
            self.data = physical
            rnp.attach_semantic_plan(plan, evidence, int(physical["rank_n_product"]))
        self.semantic_plan = plan
        return self.data
''')
once(p,
'''        cmd=[str(root/"build/topologyc"),str(core),"-o",str(output.resolve())]
''',
'''        native_compiler = root/"build/topologyc-rankn" if "rank_n_product" in data else root/"build/topologyc"
        cmd=[str(native_compiler),str(core),"-o",str(output.resolve())]
''')

# WH structural surface uses the identical physicalizer after its own semantic
# metadata has been formed, so WH/WHEX share one proof and one product mapping.
p = ROOT / "surface/wh_structural.py"
once(p, "import whex_semantics as ws\n", "import whex_semantics as ws\nimport rank_n_product as rnp\n")
once(p,
'''        self.semantic_plan = plan
        return self.data
''',
'''        try:
            physical, evidence = rnp.physicalize(self.data)
        except rnp.RankNPhysicalizationError as exc:
            raise wh.SurfaceError(str(exc)) from exc
        if evidence:
            self.data = physical
            rnp.attach_semantic_plan(plan, evidence, int(physical["rank_n_product"]))
        self.semantic_plan = plan
        return self.data
''')

# WH driver chooses the Rank-N compiler before native compilation. There is no
# failure-driven retry between lanes.
p = ROOT / "wheelchairc.py"
once(p,
'''def _compile_native(core_bytes: bytes, output: Path, executors: int) -> tuple[int,str,str]:
    with tempfile.TemporaryDirectory(prefix='wheelchair_surface_') as td:
        core=Path(td)/'program.core.wh'; core.write_bytes(core_bytes)
        cmd=[str(ROOT/'build/topologyc'),str(core),'-o',str(output)]
''',
'''def _compile_native(core_bytes: bytes, output: Path, executors: int, *, rank_n: bool=False) -> tuple[int,str,str]:
    with tempfile.TemporaryDirectory(prefix='wheelchair_surface_') as td:
        core=Path(td)/'program.core.wh'; core.write_bytes(core_bytes)
        compiler=ROOT/'build/topologyc-rankn' if rank_n else ROOT/'build/topologyc'
        cmd=[str(compiler),str(core),'-o',str(output)]
''')
once(p,
'''        rc,out,err=_compile_native(blob,a.output,a.executors)
''',
'''        rc,out,err=_compile_native(blob,a.output,a.executors,rank_n=("rank_n_product" in data))
''')

# Build the old 1.2.1 compiler/runtime unchanged, then derive a separate Rank-N
# pair from byte-verified protected sources.
p = ROOT / "build.sh"
once(p,
'''./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
''',
'''./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_runtime_template" compiler/runtime_offsets.inc

python3 tools/generate_rankn_backend_122.py
as --64 "$BUILD/generated_122/tensor_rankn_runtime_template_x86_64.S" -o "$BUILD/tensor_rankn_runtime_template.o"
ld -nostdlib -static -z noexecstack -T runtime/tensor_runtime.ld \\
  "$BUILD/tensor_rankn_runtime_template.o" -o "$BUILD/tensor_rankn_runtime_template"
./tools/generate_tensor_runtime_offsets.sh "$BUILD/tensor_rankn_runtime_template" "$BUILD/runtime_rankn_offsets.inc"
rankn_va=$(nm -n "$BUILD/tensor_rankn_runtime_template" | awk '$3=="rank_n_product_patch" {print "0x"$1; exit}')
[ -n "$rankn_va" ]
printf '.equ RUNTIME_RANK_N_PRODUCT_OFF, 0x%x\\n' $((rankn_va-0x400000)) >> "$BUILD/runtime_rankn_offsets.inc"

as --64 runtime/general_runtime_template_x86_64.S -o "$BUILD/general_runtime_template.o"
''')
once(p,
'''ld -nostdlib -static -z noexecstack \\
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend.o" "$BUILD/general_frontend.o" \\
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" \\
  -o "$BUILD/topologyc"

# Execution Fabric remains a distinct native runtime layer.
''',
'''ld -nostdlib -static -z noexecstack \\
  "$BUILD/topologyc_core.o" "$BUILD/tensor_frontend.o" "$BUILD/general_frontend.o" \\
  "$BUILD/runtime_blob.o" "$BUILD/general_runtime_blob.o" \\
  -o "$BUILD/topologyc"

as --64 "$BUILD/generated_122/tensor_rankn_frontend_x86_64.S" -o "$BUILD/tensor_rankn_frontend.o"
as --64 "$BUILD/generated_122/runtime_rankn_blob_x86_64.S" -o "$BUILD/runtime_rankn_blob.o"
ld -nostdlib -static -z noexecstack \\
  "$BUILD/topologyc_core.o" "$BUILD/tensor_rankn_frontend.o" "$BUILD/general_frontend.o" \\
  "$BUILD/runtime_rankn_blob.o" "$BUILD/general_runtime_blob.o" \\
  -o "$BUILD/topologyc-rankn"

# Execution Fabric remains a distinct native runtime layer.
''')
once(p,
'''for f in "$BUILD/topologyc" "$BUILD/tensor_runtime_template" "$BUILD/general_runtime_template" "$BUILD/topology-fabric" "$BUILD/topology-fabric-run"; do
''',
'''for f in "$BUILD/topologyc" "$BUILD/topologyc-rankn" "$BUILD/tensor_runtime_template" "$BUILD/tensor_rankn_runtime_template" "$BUILD/general_runtime_template" "$BUILD/topology-fabric" "$BUILD/topology-fabric-run"; do
''')

print("WHEELCHAIR_1_2_2_SOURCE_PATCH=PASS")
