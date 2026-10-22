#!/usr/bin/env python3
"""Explicitly refresh the public Ethereum snapshot; never invoked by forge tests.

Requires Python's standard library and curl. Fetches actual runtime code, every
storage slot reported by eth_createAccessList, and raw eth_call return values
for the supplied vectors. Does not access a wallet or submit transactions.
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FROGS = "0x4d9bfbafe31ec18e9d3066f1475e24906d155d67"
ART = "0x2a0140bc2b117ffee9b092af1a927b96328fb000"
TRAIT_SELECTOR = "0x027c00a0"  # traitSVG(uint8,uint8)
READ_SELECTOR = "0xed2e5a97"  # read(uint256)


def calldata(selector, *args):
    return selector + "".join(f"{arg:064x}" for arg in args)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc", default="https://ethereum-rpc.publicnode.com")
    parser.add_argument("--block", default="finalized", help="Block number or RPC block tag")
    args = parser.parse_args()

    def rpc(method, params):
        body = json.dumps(dict(jsonrpc="2.0", id=1, method=method, params=params)).encode()
        response = subprocess.run(
            ["curl", "--fail", "--silent", "--show-error", "--max-time", "40", args.rpc,
             "-H", "Content-Type: application/json", "--data-binary", "@-"],
            input=body, capture_output=True, check=True,
        )
        payload = json.loads(response.stdout)
        if "error" in payload:
            raise RuntimeError(f"{method}: {payload['error']}")
        return payload["result"]

    assert int(rpc("eth_chainId", []), 16) == 1, "Snapshot requires Ethereum mainnet"
    block_arg = hex(int(args.block)) if args.block.isdecimal() else args.block
    block = rpc("eth_getBlockByNumber", [block_arg, False])
    tag = block["number"]
    vectors = json.loads((ROOT / "test/fixtures/vectors.json").read_text())
    queries = {(ART, calldata(READ_SELECTOR, i)) for i in [0, 3]}
    for vector in vectors:
        queries.update((FROGS, calldata(TRAIT_SELECTOR, layer, index)) for layer, index in enumerate(vector["traits"]))

    def capture_call(query):
        target, data = query
        call = {"to": target, "data": data}
        result = rpc("eth_call", [call, tag])
        access = rpc("eth_createAccessList", [call, tag])
        if "error" in access:
            raise RuntimeError(access["error"])
        return dict(to=target, data=data, result=result), access["accessList"]

    accounts = {FROGS: set(), ART: set()}
    calls = []
    with ThreadPoolExecutor(max_workers=4) as pool:
        for call, access in pool.map(capture_call, sorted(queries)):
            calls.append(call)
            for entry in access:
                accounts.setdefault(entry["address"].lower(), set()).update(entry["storageKeys"])

    def capture_account(entry):
        address, keys = entry
        code = rpc("eth_getCode", [address, tag])
        assert code != "0x", f"Expected deployed code at {address}"
        slots = [dict(slot=key, value=rpc("eth_getStorageAt", [address, key, tag])) for key in sorted(keys)]
        return dict(account=address, code=code, slots=slots)

    with ThreadPoolExecutor(max_workers=4) as pool:
        captured = list(pool.map(capture_account, sorted(accounts.items())))
    # Refuse to save a capture if the selected block changed during acquisition.
    assert rpc("eth_getBlockByNumber", [tag, False])["hash"] == block["hash"]
    snapshot = dict(
        chainId=1,
        blockNumber=int(tag, 16),
        blockHash=block["hash"],
        blockTimestamp=int(block["timestamp"], 16),
        rpc=args.rpc,
        accounts=captured,
        calls=calls,
    )
    destination = ROOT / "test/fixtures/mainnet.json"
    destination.write_text(json.dumps(snapshot, indent=2) + "\n")
    print(f"Captured block {snapshot['blockNumber']} ({snapshot['blockHash']}): "
          f"{len(calls)} calls, {len(captured)} accounts, "
          f"{sum(len(a['slots']) for a in captured)} storage slots; {destination.stat().st_size} bytes")


if __name__ == "__main__":
    main()
