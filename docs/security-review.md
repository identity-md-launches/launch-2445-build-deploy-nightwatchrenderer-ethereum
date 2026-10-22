# Focused implementation review

This review covers `src/NightWatchRenderer.sol` and its test boundaries. It is a
local implementation review, not an independent security audit or a review of
the separately deployed NFT and artwork contracts.

- **Entry points and privileges:** the compiled ABI exposes only the requested
  `svg` view function and the `InvalidTier` error. All helper functions and
  dependency constants are private. The storage layout is empty. There is no
  fallback, receive, admin, initializer, proxy, or library link placeholder.
- **Construction:** no arguments, external calls, ownership assignment, or
  deployment-chain dependency checks. A test removes both dependencies and
  successfully constructs the application. Creation value must be zero.
- **External calls:** interfaces are view functions; EVM tracing verifies nine
  direct STATICCALLs for tier 6, exclusively to the two specified addresses.
  Other tiers have eight. A dependency attempting SSTORE fails in static context.
  Revert data is allowed to bubble; missing code and malformed ABI data fail
  instead of returning partial output.
- **Value and storage:** ordinary ETH transfers and ETH-bearing render calls
  revert. No value is sent externally and the renderer makes no storage accesses.
  Forced ETH is an EVM limitation; it creates no withdrawal entitlement or
  recovery function. There is no accounting or value-changing reentrancy surface.
- **Arithmetic:** invalid tiers are rejected before color selection and ember
  arithmetic. Ember loops have 6, 10, 14, or 18 iterations. There are exactly five
  pips, seven trait reads, and ten source numbers. Decimal conversion has at most
  78 digits; the plate coordinate stays at most 1,690. A decimal digit cast is
  bounded to ASCII 48–57. Zero and maximum inputs and digit-count boundaries are
  explicitly exercised and fuzzed.
- **Byte fidelity:** all five independent expected hashes pass against captured
  mainnet bytecode. Tests cover the otherwise absent tier 4, ordering,
  inclusive ember endpoints, conditional animation, Captain art, accessory
  badges, label preservation, and source order. Labels are raw by requirement;
  this contract does not sanitize arbitrary active SVG content or attest that
  the displayed fields describe a real NFT. Integrators own those checks.
- **Deployment bounds:** runtime is 11,772 bytes and creation code is 11,798
  bytes. Inspection found no linked libraries. The supplied protected floor's
  reachable-opcode scan was reproduced locally and found no DELEGATECALL,
  CALLCODE, or SELFDESTRUCT in reachable renderer instructions.

Validation uses Foundry 1.8.3 and solc 0.8.26 with the assignment's fuzz seed. The
suite includes 31 tests and four 256-run fuzz cases. The captured external-art
calls are independently replayed against the saved raw RPC responses. Cold gas
benchmarks use the actual captured dependencies, not response mocks.

Slither and Mythril were not run. No live transaction was signed or broadcast,
and no deployed renderer address or explorer verification is claimed. The
upstream dependencies' future availability, arbitrary label resource exhaustion,
browser animation/font differences, and NFT-level economic rules are outside
the local regression guarantee. The launch operator must perform the documented
post-deployment runtime comparison, live vector calls, and source verification.
