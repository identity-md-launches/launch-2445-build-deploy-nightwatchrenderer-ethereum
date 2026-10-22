# Renderer tests

All tests run offline using the vendored forge-std and checked-in artwork fixture.
No RPC endpoint, fork, FFI, environment mutation, or additional dependency is needed.

The original `NightWatchRendererVectors.t.sol` retains the five supplied hash
vectors, exact README image comparisons, and cold gas measurements.
`NightWatchRenderer.t.sol` retains the tier boundaries, decimal boundaries,
argument forwarding, and original failure cases.

Additional coverage:

- `NightWatchRendererDependencies.t.sol`: each of the nine possible dependency
  calls, arbitrary raw return/revert bytes, empty strings, ABI word boundaries,
  malformed return data, missing frog code, and Captain-only failures. Write
  probes are reached through ordinary `CALL`, so static behavior must be enforced
  by the renderer itself.
- `NightWatchRendererProperties.t.sol`: entire-output comparisons after changing
  one label, source number, point value, or accessory; binary labels; duplicate
  sources; all-tier badge boundaries; caller/block independence; exact external
  call arguments and counts; no storage access or logs during ordinary calls;
  ETH rejection; malformed calldata; and interleaved renders in one transaction.
- `NightWatchRendererTierFour.t.sol`: the missing tier-4 vector is checked against
  the supplied Supervisor image/hash plus the literal tier-3-to-tier-4 changes
  from the brief. This expected result is not obtained from the renderer. A cold
  gas measurement also covers tier 4.

The synthetic dependency probes are separate from the real-artwork fixture.
Substitution properties compare every output byte, while the supplied hashes
anchor the overall artwork. Probe trait art intentionally ignores the trait
index to isolate accessory behavior; independent call tracing checks every index
is forwarded unchanged. New fuzz properties each run 512 cases via inline config.

The application has no payable operation, stored balances, or accounting state,
so there is no custody invariant handler. Ordinary-call tracing, ETH-rejection
properties, and the transaction sequence probe cover its stateless boundary.
These tests do not claim that an EVM address cannot be forcibly credited with ETH.

Run from the repository root (build products stay in disposable scratch space):

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x8722dd41e9b06c1fcb1e0ba7f8f4c474496ed13e520f2f93221c331e47865edd forge test --out test/scratch/out --cache-path test/scratch/cache
```

This test contribution does not deploy contracts or perform explorer verification.
