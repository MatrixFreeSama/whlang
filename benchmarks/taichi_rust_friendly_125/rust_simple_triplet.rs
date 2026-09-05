use std::env;
use std::thread;

#[inline(always)]
fn uval(i: u64) -> f64 {
    0.25 + (((17u64.wrapping_mul(i).wrapping_add(3)) & 1023) as f64) * (1.0 / 1024.0)
}
#[inline(always)]
fn pval(i: u64) -> f64 {
    -0.125 + (((29u64.wrapping_mul(i).wrapping_add(7)) & 1023) as f64) * (1.0 / 1024.0)
}
#[inline(always)]
fn xval(i: u64) -> f64 {
    -0.375 + (((31u64.wrapping_mul(i).wrapping_add(5)) & 1023) as f64) * (1.0 / 1024.0)
}

fn range_sum(workload: &str, n: u64, lo: u64, hi: u64) -> f64 {
    let mut s = 0.0f64;
    match workload {
        "heat" => {
            for i in lo..hi {
                let im = if i == 0 { n - 1 } else { i - 1 };
                let ip = if i + 1 == n { 0 } else { i + 1 };
                let u = uval(i);
                s += u + 0.125 * (uval(im) - 2.0 * u + uval(ip));
            }
        }
        "wave" => {
            for i in lo..hi {
                let im = if i == 0 { n - 1 } else { i - 1 };
                let ip = if i + 1 == n { 0 } else { i + 1 };
                let u = uval(i);
                s += 2.0 * u - pval(i) + 0.0625 * (uval(im) - 2.0 * u + uval(ip));
            }
        }
        "sparse" => {
            for i in lo..hi {
                let x = xval(i);
                let j1 = (17u64.wrapping_mul(i).wrapping_add(3)) % n;
                let j2 = (29u64.wrapping_mul(i).wrapping_add(7)) % n;
                let j3 = (43u64.wrapping_mul(i).wrapping_add(11)) % n;
                s += 1.75 * x - 0.125 * xval(j1) + 0.0625 * xval(j2) - 0.03125 * xval(j3)
                    + 0.015625 * x * x * x;
            }
        }
        _ => panic!("unknown workload"),
    }
    s
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("usage: rust_simple_triplet <heat|wave|sparse> <n> <threads>");
        std::process::exit(2);
    }
    let workload = args[1].clone();
    let n: u64 = args[2].parse().unwrap();
    let q: usize = args[3].parse().unwrap();
    assert!(n > 0 && q > 0);

    let mut parts = vec![0.0f64; q];
    thread::scope(|scope| {
        let mut handles = Vec::with_capacity(q);
        for t in 0..q {
            let w = &workload;
            let lo = (n * t as u64) / q as u64;
            let hi = (n * (t as u64 + 1)) / q as u64;
            handles.push(scope.spawn(move || range_sum(w, n, lo, hi)));
        }
        for (t, h) in handles.into_iter().enumerate() {
            parts[t] = h.join().unwrap();
        }
    });
    let total: f64 = parts.into_iter().sum();
    println!("checksum={:.17} checksum_bits=0x{:016x}", total, total.to_bits());
}
