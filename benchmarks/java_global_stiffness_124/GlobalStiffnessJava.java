import java.util.Arrays;
import java.util.Locale;
import java.util.concurrent.*;

public final class GlobalStiffnessJava {
    static final long CHUNK = 65536L;

    static double xval(long i) {
        return -0.5 + (double) ((i * 29L + 7L) & 1023L) * (1.0 / 1024.0);
    }

    static double kval(long i) {
        return 1.0 + (double) ((i * 17L + 3L) & 255L) * (1.0 / 1024.0);
    }

    static double slot(long i, long n) {
        long im1 = (i == 0) ? n - 1 : i - 1;
        long ip1 = (i + 1 == n) ? 0 : i + 1;
        double ki = kval(i);
        double kip = kval(ip1);
        double yi = (ki + kip) * xval(i) - ki * xval(im1) - kip * xval(ip1);
        return yi * yi;
    }

    static double chunkSum(long k, long n) {
        long s = k * CHUNK;
        long end = Math.min(s + CHUNK, n);
        double a0 = 0.0, a1 = 0.0, a2 = 0.0, a3 = 0.0;
        long i = s;
        for (; i + 4 <= end; i += 4) {
            a0 += slot(i, n);
            a1 += slot(i + 1, n);
            a2 += slot(i + 2, n);
            a3 += slot(i + 3, n);
        }
        if (i < end) a0 += slot(i++, n);
        if (i < end) a1 += slot(i++, n);
        if (i < end) a2 += slot(i, n);
        return (a0 + a1) + (a2 + a3);
    }

    static double treeReduce(double[] partials, int m) {
        while (m > 1) {
            int w = 0;
            int i = 0;
            for (; i + 1 < m; i += 2) partials[w++] = partials[i] + partials[i + 1];
            if ((m & 1) != 0) partials[w++] = partials[m - 1];
            m = w;
        }
        return partials[0];
    }

    static final class Runner implements AutoCloseable {
        final int q;
        final ExecutorService pool;
        Runner(int q) {
            this.q = q;
            this.pool = q == 1 ? null : Executors.newFixedThreadPool(q, r -> {
                Thread t = new Thread(r, "stiffness-worker");
                t.setDaemon(true);
                return t;
            });
        }

        double compute(long n) throws Exception {
            int chunks = (int) ((n + CHUNK - 1) / CHUNK);
            double[] partials = new double[chunks];
            if (q == 1) {
                for (int k = 0; k < chunks; ++k) partials[k] = chunkSum(k, n);
            } else {
                Future<?>[] fs = new Future<?>[q];
                for (int e = 0; e < q; ++e) {
                    final int ee = e;
                    fs[e] = pool.submit(() -> {
                        for (int k = ee; k < chunks; k += q) partials[k] = chunkSum(k, n);
                    });
                }
                for (Future<?> f : fs) f.get();
            }
            return treeReduce(partials, chunks);
        }

        public void close() {
            if (pool != null) pool.shutdownNow();
        }
    }

    public static void main(String[] args) throws Exception {
        Locale.setDefault(Locale.ROOT);
        if (args.length != 4) throw new IllegalArgumentException("n q warm runs");
        long n = Long.parseLong(args[0]);
        int q = Integer.parseInt(args[1]);
        int warm = Integer.parseInt(args[2]);
        int runs = Integer.parseInt(args[3]);
        if (n < 4 || n > 100_000_000L || (q != 1 && q != 2 && q != 4)) throw new IllegalArgumentException();

        try (Runner r = new Runner(q)) {
            double first = r.compute(n);
            for (int i = 0; i < warm; ++i) r.compute(n);
            double[] samples = new double[runs];
            double maxDrift = 0.0;
            for (int i = 0; i < runs; ++i) {
                long t0 = System.nanoTime();
                double v = r.compute(n);
                long t1 = System.nanoTime();
                samples[i] = (t1 - t0) / 1e6;
                maxDrift = Math.max(maxDrift, Math.abs(v - first) / Math.max(Math.abs(first), 1.0));
            }
            Arrays.sort(samples);
            double median = samples[runs / 2];
            long bits = Double.doubleToRawLongBits(first);
            System.out.printf("JAVA N=%d Q=%d MEDIAN_MS=%.6f MIN_MS=%.6f MAX_MS=%.6f CHECKSUM_BITS=0x%016x DRIFT=%.3e%n",
                    n, q, median, samples[0], samples[runs - 1], bits, maxDrift);
        }
    }
}
