// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console2} from "forge-std/console2.sol";
import {MainnetFixture} from "../test/helpers/MainnetFixture.sol";

/// @dev Local-only preview generation. Never broadcasts; uses the committed mainnet snapshot.
contract RenderExamples is MainnetFixture {
    function run() public {
        _loadMainnet();
        for (uint256 i; i < 5; ++i) {
            Vector memory v = _vector(i);
            string memory result = _render(v);
            assertEq(keccak256(bytes(result)), v.hash, "preview must match supplied vector");
            console2.log(string.concat("IMAGE:", v.name, ":", vm.toString(bytes(result))));
        }
    }
}
