#!/usr/bin/env python3
from __future__ import annotations
import argparse,csv,json,statistics,subprocess,sys,time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'worktree'/'surface'))
import schedulerless_causal_plan as sc

def graph(name:str,n:int):
    nodes=[str(i) for i in range(n)]
    if name=='chain': edges=[[str(i),str(i+1)] for i in range(n-1)]
    elif name=='binary_tree':
        edges=[]
        for i in range(n):
            for c in (2*i+1,2*i+2):
                if c<n: edges.append([str(i),str(c)])
    elif name=='layered':
        edges=[]; width=7; first=list(range(1,min(n,1+width)))
        for v in first: edges.append(['0',str(v)])
        prev=first; nxt=max(first,default=0)+1
        while nxt<n:
            cur=list(range(nxt,min(n,nxt+width)))
            for k,v in enumerate(cur):
                for u in (prev[k%len(prev)],prev[(k+3)%len(prev)]): edges.append([str(u),str(v)])
            prev=cur; nxt=cur[-1]+1
        edges=edges[:256]
    else: raise ValueError(name)
    return nodes,edges

def timed(cmd,reps,warmups=2):
    samples=[]; payload=None
    for k in range(warmups+reps):
        t0=time.perf_counter_ns(); cp=subprocess.run(cmd,capture_output=True,text=True,check=False); t1=time.perf_counter_ns()
        if cp.returncode: raise RuntimeError(f"rc={cp.returncode} cmd={cmd}: {cp.stdout}{cp.stderr}")
        if k>=warmups: samples.append(t1-t0)
        if cp.stdout.strip().startswith('{'): payload=json.loads(cp.stdout)
    return int(statistics.median(samples)),payload

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--out',type=Path,default=ROOT/'benchmarks'/'schedulerless_causal_126'/'results.csv'); ap.add_argument('--reps',type=int,default=5); a=ap.parse_args()
    new=ROOT/'worktree'/'build'/'topology-fabric-schedulerless'; old=ROOT/'worktree'/'build'/'topology-fabric-run'; c=ROOT/'benchmarks'/'schedulerless_causal_126'/'expert_c_causal_q1'
    rows=[]
    for topology,n in [('chain',64),('binary_tree',63),('layered',57)]:
        nodes,edges=graph(topology,n)
        for work in (0,1000,20000):
            spec={'format':sc.FORMAT,'nodes':[{'id':x,'work':work} for x in nodes],'edges':edges}
            for slots in (1,2,4):
                p=sc.plan(spec,slots); argv=p['native_argv']
                n_ns,n_payload=timed([str(new),*argv],a.reps); o_ns,o_payload=timed([str(old),*argv],a.reps)
                row={'topology':topology,'nodes':n,'edges':len(edges),'work_iters':work,'slots':slots,'schedulerless_ns':n_ns,'fabric_125_ns':o_ns,'schedulerless_over_125':n_ns/o_ns,'direct_continuations':n_payload['direct_continuations'],'remote_handoffs':n_payload['remote_handoffs'],'handoff_collisions':n_payload['handoff_collisions'],'slot_waits':n_payload['slot_waits'],'global_ready_scans':n_payload['global_ready_scans'],'global_queue_ops':n_payload['global_queue_ops'],'root_scheduler_ops':n_payload['root_scheduler_ops'],'parent_chain_updates':n_payload['parent_chain_updates']}
                if slots==1:
                    c_ns,c_payload=timed([str(c),*argv],a.reps); row['expert_c_q1_ns']=c_ns; row['schedulerless_over_expert_c_q1']=n_ns/c_ns
                else: row['expert_c_q1_ns']=''; row['schedulerless_over_expert_c_q1']=''
                rows.append(row); print(json.dumps(row,separators=(',',':')))
    a.out.parent.mkdir(parents=True,exist_ok=True)
    with a.out.open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
    assert all(r['global_ready_scans']==0 and r['global_queue_ops']==0 and r['root_scheduler_ops']==0 and r['parent_chain_updates']==0 for r in rows)
    print('SCHEDULERLESS_CAUSAL_BENCHMARK_MATRIX=PASS')
if __name__=='__main__': main()
