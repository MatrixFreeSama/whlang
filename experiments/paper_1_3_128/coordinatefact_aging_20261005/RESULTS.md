# Wheelchair 1.3.128 native256 CoordinateFact aging

One pinned CPU `0`, 9 interleaved repetitions, Strict FP, x86-64-v3/native256. 1.3.127 and 1.3.128 checksums are bit-identical at every point.

| workload | n | 1.3.127 ms | 1.3.128 ms | C ms | 128/127 speedup | 128/C speedup |
|---|---:|---:|---:|---:|---:|---:|
| miniAMR_27point | 160 | 122.881658 | 28.712282 | 38.719725 | 4.280x | 1.349x |
| miniAMR_27point | 192 | 180.159799 | 43.186261 | 65.733845 | 4.172x | 1.522x |
| miniAMR_27point | 224 | 246.046756 | 63.244176 | 103.467785 | 3.890x | 1.636x |
| miniAMR_27point | 256 | 92.715388 | 80.773478 | 154.513634 | 1.148x | 1.913x |
| miniFE_heat21 | 160 | 100.001397 | 25.022701 | 23.800579 | 3.996x | 0.951x |
| miniFE_heat21 | 192 | 146.466302 | 37.644218 | 40.100867 | 3.891x | 1.065x |
| miniFE_heat21 | 224 | 200.575518 | 53.934107 | 63.033595 | 3.719x | 1.169x |
| miniFE_heat21 | 256 | 75.048330 | 67.889198 | 94.537291 | 1.105x | 1.393x |

The change introduces no workload matcher, extent threshold, second Field backend, JIT, scheduler, or source-visible parallel construct. Native256 now retains one canonical packet CoordinateFact in an execution-local physical carrier; AddressFacts consume it instead of re-deriving Rank-N coordinates independently.
