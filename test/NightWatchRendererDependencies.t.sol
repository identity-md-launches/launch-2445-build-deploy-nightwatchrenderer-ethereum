// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {RendererProbes} from "./helpers/RendererProbes.sol";
import {IArtStore} from "src/NightWatchRenderer.sol";

contract WritingDependencyProbe {
    fallback() external {
        assembly {
            sstore(0, 1)
            mstore(0, 32)
            mstore(32, 0)
            return(0, 64)
        }
    }
}

contract CaptainWritingProbe {
    uint256 private writes;

    function read(uint256 index) external returns (string memory) {
        if (index == 0) return "<probe-base/>";
        require(index == 3, "unexpected index");
        ++writes;
        return "<probe-captain/>";
    }
}

/// @dev Entire-output substitution properties check byte fidelity without drawing
/// a second SVG in the test. Each of the nine dependency positions is exercised.
/// forge-config: default.fuzz.runs = 512
contract NightWatchRendererDependenciesTest is RendererProbes {
    function testFuzz_dependencyBytesChangeOnlyTheirOwnFragment(uint8 rawSlot, uint8 rawTier, bytes memory artwork)
        public
    {
        uint256 slot = bound(rawSlot, 0, 8);
        uint8 tier = slot == 8 ? 6 : uint8(bound(rawTier, 1, 6));
        _checkSubstitution(slot, tier, artwork);
    }

    function test_emptyStringsAreValidAtEveryDependencyPosition() public {
        for (uint256 slot; slot < 9; ++slot) {
            _checkSubstitution(slot, 6, "");
        }
    }

    function test_dependencyBytesAcrossAbiWordBoundaries() public {
        uint256[9] memory lengths = [uint256(1), 31, 32, 33, 63, 64, 65, 257, 4096];
        for (uint256 i; i < lengths.length; ++i) {
            bytes memory payload = new bytes(lengths[i]);
            for (uint256 j; j < payload.length; ++j) {
                payload[j] = j % 3 == 0 ? bytes1(0) : j % 3 == 1 ? bytes1(0xff) : bytes1(0x22);
            }
            // Rotate through all seven layers, BASE and the Captain overlay.
            _checkSubstitution(i, 6, payload);
        }
    }

    function testFuzz_everyDependencyFailureBubblesUnchanged(uint8 rawSlot, bytes memory reason) public {
        _checkRevert(bound(rawSlot, 0, 8), reason);
    }

    function test_emptyCustomErrorAndPanicRevertsAtEveryPosition() public {
        for (uint256 slot; slot < 9; ++slot) {
            _checkRevert(slot, "");
            _checkRevert(slot, abi.encodeWithSignature("ArtworkUnavailable(uint256)", slot));
            _checkRevert(slot, abi.encodeWithSignature("Panic(uint256)", 0x32));
        }
    }

    function test_malformedAbiAtEveryDependencyPosition() public {
        bytes[8] memory malformed = [
            bytes(""),
            hex"01",
            abi.encode(uint256(32)),
            abi.encode(uint256(32), uint256(1)),
            abi.encode(type(uint256).max, uint256(0)),
            abi.encode(uint256(32), type(uint256).max),
            abi.encode(uint256(64), uint256(0)),
            abi.encode(uint256(32), uint256(33), bytes32(0))
        ];
        for (uint256 slot; slot < 9; ++slot) {
            (address target, bytes memory data,) = _dependency(slot);
            for (uint256 i; i < malformed.length; ++i) {
                vm.mockCall(target, data, malformed[i]);
                (bool ok,) = address(renderer).call{gas: 2_000_000}(_callData(6));
                assertFalse(ok, "malformed dependency ABI produced an SVG");
                vm.clearMockedCalls();
            }
        }
    }

    function test_captainFailureDoesNotBreakOtherTiers() public {
        string[5] memory expected;
        for (uint8 tier = 1; tier <= 5; ++tier) {
            expected[tier - 1] = _render(tier);
        }
        bytes memory reason = abi.encodeWithSignature("CaptainUnavailable()");
        vm.mockCallRevert(ART, abi.encodeCall(IArtStore.read, (3)), reason);
        for (uint8 tier = 1; tier <= 5; ++tier) {
            assertEq(_render(tier), expected[tier - 1], "lower tier depends on Captain art");
        }
        (bool ok, bytes memory actual) = address(renderer).call(_callData(6));
        assertFalse(ok, "Captain rendered without its required overlay");
        assertEq(actual, reason);
    }

    function test_missingFrogsCodeRevertsForEveryTier() public {
        vm.etch(FROGS, "");
        for (uint8 tier = 1; tier <= 6; ++tier) {
            (bool ok,) = address(renderer).call(_callData(tier));
            assertFalse(ok, "missing frog renderer silently omitted the subject");
        }
    }

    function testFuzz_dependenciesCannotWriteDuringOrdinaryCall(bool frogs, uint8 rawTier) public {
        address target = frogs ? FROGS : ART;
        vm.etch(target, address(new WritingDependencyProbe()).code);
        // Use CALL at the top level. STATICCALL here would mask a renderer which
        // accidentally used CALL for its dependencies.
        (bool ok,) = address(renderer).call{gas: 2_000_000}(_callData(uint8(bound(rawTier, 1, 6))));
        assertFalse(ok, "dependency was allowed to write");
        assertEq(vm.load(target, bytes32(0)), bytes32(0));
    }

    function test_captainReadIsAlsoStaticDuringOrdinaryCall() public {
        vm.etch(ART, address(new CaptainWritingProbe()).code);
        (bool lowerTier,) = address(renderer).call(_callData(5));
        assertTrue(lowerTier, "probe must work until read(3)");
        (bool captain,) = address(renderer).call{gas: 2_000_000}(_callData(6));
        assertFalse(captain, "Captain read allowed a storage write");
        assertEq(vm.load(ART, bytes32(0)), bytes32(0));
    }

    function _checkSubstitution(uint256 slot, uint8 tier, bytes memory payload) private {
        string memory baseline = _render(tier);
        (address target, bytes memory data, string memory marker) = _dependency(slot);
        string memory expected = _replaceOnce(baseline, marker, payload);
        vm.mockCall(target, data, abi.encode(string(payload)));
        assertEq(bytes(_render(tier)), bytes(expected), "dependency bytes escaped, reordered, duplicated or truncated");
        vm.clearMockedCalls();
        assertEq(_render(tier), baseline, "dependency response was cached");
    }

    function _checkRevert(uint256 slot, bytes memory reason) private {
        (address target, bytes memory data,) = _dependency(slot);
        vm.mockCallRevert(target, data, reason);
        (bool ok, bytes memory actual) = address(renderer).call(_callData(6));
        assertFalse(ok, "failed dependency produced a partial SVG");
        assertEq(actual, reason, "dependency revert data was replaced");
        vm.clearMockedCalls();
    }
}
