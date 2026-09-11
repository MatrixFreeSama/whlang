# Wheelchair 1.0.13 True-Parallel A/B

Host observed in this execution image: Intel Xeon Platinum 8272CL @ 2.60 GHz, 5 online logical CPUs.

Workload: existing periodic heat WHEX topology, N=16,777,216, one executor, checksum `0x4167fc0000000000`.

Method: four warmups per binary followed by 31+31 interleaved whole-process measurements in deterministic shuffled order.

```text
Wheelchair 1.0.12 median: 37.280716 ms
Wheelchair 1.0.13 median: 31.723609 ms
median speedup:          1.175173x

1.0.12 minimum:          32.472896 ms
1.0.13 minimum:          27.924239 ms
```

This report is a same-host Wheelchair-version A/B only. The current execution image does not provide the Rust 1.98 toolchain, so these measurements are not presented as a renewed Rust-versus-Wheelchair result.

Machine-code change relevant to the prior Rust gap:

```text
1.0.12: repeated affine coefficient multiplication inside each vector evaluator entry
1.0.13 init: c*root initialized once
1.0.13 loop: persistent carrier += c*8
```

For the existing coefficient 17 probe, the generated loop contains an exact `+136` recurrence.
