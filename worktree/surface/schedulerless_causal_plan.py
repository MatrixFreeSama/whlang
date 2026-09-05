#!/usr/bin/env python3
"""Wheelchair 1.2.6 compile-time Schedulerless Sparse Causal plan.

Workload-name blind AOT placement/readiness evidence. No runtime runnable queue,
dispatcher, cost selector, work stealing, root epoch, or serial fallback is emitted.
"""
from __future__ import annotations
import argparse, hashlib, json
from collections import deque
from pathlib import Path
from typing import Any

FORMAT="wheelchair.schedulerless_causal/1"
MAX_NODES=64
MAX_EDGES=256
MAX_SLOTS=16

class SchedulerlessCausalError(ValueError): pass

class Node:
    __slots__=("id","work")
    def __init__(self,ident:str,work:int=1): self.id=ident; self.work=work

def _canon(x:Any)->str:
    return json.dumps(x,sort_keys=True,ensure_ascii=False,separators=(",",":"))

def _nodes(raw:Any)->list[Node]:
    if not isinstance(raw,list) or not raw: raise SchedulerlessCausalError("nodes must be a non-empty list")
    if len(raw)>MAX_NODES: raise SchedulerlessCausalError(f"node count exceeds bounded native proof cap {MAX_NODES}")
    out=[]; seen=set()
    for item in raw:
        if isinstance(item,str): node=Node(item,1)
        elif isinstance(item,dict):
            ident=item.get("id"); work=item.get("work",1)
            if not isinstance(ident,str) or not ident: raise SchedulerlessCausalError("every node requires a non-empty string id")
            if isinstance(work,bool) or not isinstance(work,int) or work<0 or work>0xffffffff: raise SchedulerlessCausalError(f"node {ident!r} work must be u32")
            node=Node(ident,work)
        else: raise SchedulerlessCausalError("nodes must be strings or node records")
        if node.id in seen: raise SchedulerlessCausalError(f"duplicate node id {node.id!r}")
        seen.add(node.id); out.append(node)
    return out

def _edges(raw:Any,index:dict[str,int])->list[tuple[int,int]]:
    if raw is None: raw=[]
    if not isinstance(raw,list): raise SchedulerlessCausalError("edges must be a list")
    if len(raw)>MAX_EDGES: raise SchedulerlessCausalError(f"edge count exceeds bounded native proof cap {MAX_EDGES}")
    out=[]; seen=set()
    for item in raw:
        if not isinstance(item,(list,tuple)) or len(item)!=2: raise SchedulerlessCausalError("every edge must be [producer, consumer]")
        a,b=item
        if a not in index or b not in index: raise SchedulerlessCausalError(f"edge {item!r} references an unknown node")
        u,v=index[a],index[b]
        if u==v: raise SchedulerlessCausalError("self dependency is a cycle")
        if (u,v) in seen: raise SchedulerlessCausalError(f"duplicate edge {item!r}")
        seen.add((u,v)); out.append((u,v))
    return out

def _topology(n:int,edges:list[tuple[int,int]]):
    pred=[[] for _ in range(n)]; succ=[[] for _ in range(n)]; indeg=[0]*n
    for u,v in edges: succ[u].append(v); pred[v].append(u); indeg[v]+=1
    q=deque(i for i,d in enumerate(indeg) if d==0); order=[]; level=[0]*n; rem=indeg[:]
    while q:
        u=q.popleft(); order.append(u)
        for v in succ[u]:
            level[v]=max(level[v],level[u]+1); rem[v]-=1
            if rem[v]==0: q.append(v)
    if len(order)!=n: raise SchedulerlessCausalError("causal relation contains a cycle")
    return order,pred,succ,level

def _place(nodes:list[Node],slots:int,order:list[int],pred:list[list[int]],level:list[int])->list[int]:
    # Nodes in one topological level are independent. Spread independent width
    # first, then prefer predecessor locality. This is static physical placement,
    # never a runtime profitability selector and never narrows requested width.
    home=[-1]*len(nodes); load=[0]*slots; by_level={}
    for u in order: by_level.setdefault(level[u],[]).append(u)
    for lev in sorted(by_level):
        used=set()
        for pos,u in enumerate(by_level[lev]):
            locality=[0]*slots
            for p in pred[u]:
                if home[p]>=0: locality[home[p]]+=1
            available=[s for s in range(slots) if s not in used]
            candidates=available if available else list(range(slots))
            rot=(u+lev+pos)%slots
            s=min(candidates,key=lambda x:(-locality[x],load[x],(x-rot)%slots,x))
            home[u]=s; load[s]+=max(1,nodes[u].work); used.add(s)
    return home

def plan(spec:dict[str,Any],slots:int|None=None)->dict[str,Any]:
    if not isinstance(spec,dict): raise SchedulerlessCausalError("specification must be an object")
    if spec.get("format",FORMAT)!=FORMAT: raise SchedulerlessCausalError(f"format must be {FORMAT!r}")
    nodes=_nodes(spec.get("nodes")); index={n.id:i for i,n in enumerate(nodes)}; edges=_edges(spec.get("edges",[]),index)
    if slots is None: slots=spec.get("slots",1)
    if isinstance(slots,bool) or not isinstance(slots,int) or not 1<=slots<=MAX_SLOTS: raise SchedulerlessCausalError(f"slots must be in [1,{MAX_SLOTS}]")
    order,pred,succ,level=_topology(len(nodes),edges); home=_place(nodes,slots,order,pred,level)
    sources=[u for u in order if not pred[u]]
    local_edges=sum(home[u]==home[v] for u,v in edges); cross_edges=len(edges)-local_edges
    widths={}
    for lev in level: widths[lev]=widths.get(lev,0)+1
    payload={"nodes":[n.id for n in nodes],"edges":[[nodes[u].id,nodes[v].id] for u,v in edges],"slots":slots,"home":home,"work":[n.work for n in nodes]}
    return {
      "format":"wheelchair.schedulerless_causal_plan/1","source_format":FORMAT,
      "workload_dispatch":False,"runtime_dispatch":False,"runtime_cost_selector":False,
      "requested_slots":slots,"materialized_slots":slots,"serial_fallback":0,
      "global_ready_queue":0,"global_ready_scan":0,"root_scheduler":0,"root_epoch":0,
      "parent_demand_tree":0,"work_stealing":0,"global_phase_barrier":0,"local_causal_time":True,
      "readiness_rule":"declared_dependency_zero_transition","collision_rule":"producer_private_continuation",
      "node_count":len(nodes),"edge_count":len(edges),"source_count":len(sources),"sources":[nodes[u].id for u in sources],
      "topological_depth":1+max(level,default=0),"max_ready_width":max(widths.values(),default=0),
      "local_dependency_edges":local_edges,"cross_slot_dependency_edges":cross_edges,
      "home_slots":home,"home_by_node":{nodes[i].id:home[i] for i in range(len(nodes))},
      "work_u32":[n.work for n in nodes],"edge_uv_u32":[[u,v] for u,v in edges],
      "native_argv":[str(len(nodes)),str(len(edges)),str(slots)]+[str(x) for x in home]+[str(n.work) for n in nodes]+[str(x) for e in edges for x in e],
      "structural_signature_sha256":hashlib.sha256(_canon(payload).encode()).hexdigest()
    }

def main()->int:
    ap=argparse.ArgumentParser(description="Wheelchair 1.2.6 AOT schedulerless causal planner")
    ap.add_argument("spec",type=Path); ap.add_argument("--slots",type=int,default=None); ap.add_argument("-o","--output",type=Path,default=None)
    a=ap.parse_args(); result=plan(json.loads(a.spec.read_text(encoding="utf-8")),a.slots); text=json.dumps(result,ensure_ascii=False,sort_keys=True,indent=2)+"\n"
    if a.output: a.output.write_text(text,encoding="utf-8")
    else: print(text,end="")
    return 0
if __name__=="__main__":
    try: raise SystemExit(main())
    except SchedulerlessCausalError as exc:
        import sys; print(f"schedulerless causal plan rejection: {exc}",file=sys.stderr); raise SystemExit(65)
