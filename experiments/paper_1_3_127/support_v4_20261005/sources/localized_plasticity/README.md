# Localized elastoplastic SupportFact algebra benchmark — 1.3.127

A 1D integration-point line contains a fixed-width localized stress concentration. Only about 3999 of 8,000,000 points yield; the physical plastic zone stays approximately fixed when the total elastic domain grows.

The benchmark is retained because it exposed two general SupportFact gaps in 1.3.126: superlevel CAP topology (`shape > constant`) and RegionSet propagation through multiplication/polynomial expressions. 1.3.127 closes those facts without a plasticity matcher.

`single8_raw.csv`, `four8_raw.csv`, and `scale.csv` contain the final interleaved measurements used by the release notes.
