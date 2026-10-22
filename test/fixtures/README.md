# Offline Ethereum artwork snapshot

`mainnet.json` was obtained through read-only `eth_chainId`,
`eth_getBlockByNumber`, `eth_call`, `eth_createAccessList`, and `eth_getCode`
requests to the public RPC recorded in that file. Capture code is
[`tools/capture_fixture.py`](../../tools/capture_fixture.py). All queries use the
same finalized block, 26,244,666, and the script rechecks its hash before saving.
The script can also capture reported storage slots, but none were needed here.

`calls` contains the exact ABI-encoded responses for all 23 distinct trait queries
used by the five vectors, plus `ArtStore.read(0)` and `ArtStore.read(3)`. `accounts`
contains each called account and each account reported by the corresponding
access lists, including the code-based artwork data. The latter are dependencies
of the existing contracts, not extra addresses called directly by
NightWatchRenderer.

| Account | Code bytes | Runtime keccak256 |
| --- | ---: | --- |
| `0x2a0140bc2b117ffee9b092af1a927b96328fb000` | 563 | `0xf573daa6714c7b0aadb6c6c3ee9f8a23bbb76c0b857cdd539b18b54630a4c8b8` |
| `0x4d9bfbafe31ec18e9d3066f1475e24906d155d67` | 6,459 | `0x1d1a10626037e7c0aab2d45117ba68b44e8545441ff0cb6dc8b970661b55eaf9` |
| `0x86ea846dfa548d6725094f62433c941093f696f2` | 23,865 | `0x68895ba183332b62d95d38be4a10082b7fdebe64933a4cee2839c6b745cde4a4` |
| `0xc6cc2d921a928f9d8bd68e600bc0662286fb4bbe` | 16,505 | `0xb8e148d694aca65f87694832674a023a7884bdb818b6a9fd0998de6d295b389b` |
| `0xf87acd914aa12b344a33ad4fc8966f85db3bfafd` | 563 | `0x401ad670536998f332a813ad18ced5bc99408ce84e86b5b89000a9d2290bb43b` |

Tests install the captured runtime with `vm.etch` and execute it. They compare
every captured response and all five final SVG hashes against the requester's
vectors. The hashes are additionally literal constants in the Solidity tests,
and the README images must equal the rendered bytes. Unit tests use clearly
separate synthetic dependencies for hostile responses and unconstrained traits.

This is a finite regression fixture, not an independently verified Ethereum
state proof or a guarantee of future RPC responses. It does not audit the external
contracts or enumerate their entire trait catalog. Re-capture deliberately, review
changes, and retain the supplied vector hashes; do not regenerate expected hashes
from the implementation under test. All artwork bytes, including BASE newlines,
are preserved without modification.
