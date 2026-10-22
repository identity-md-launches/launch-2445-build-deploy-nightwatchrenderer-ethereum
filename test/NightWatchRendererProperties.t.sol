// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {VmSafe} from "forge-std/Vm.sol";
import {RendererProbes} from "./helpers/RendererProbes.sol";
import {NightWatchRenderer, INightFrogsRenderer, IArtStore} from "src/NightWatchRenderer.sol";

/// @dev One external invocation puts all four calls in the same EVM transaction,
/// including on Foundry versions that isolate top-level calls from the test.
contract RenderSequenceProbe {
    function renderSequence(address target, bytes calldata first, bytes calldata different, bytes calldata invalid)
        external
        returns (bytes memory before_, bytes memory after_, bytes memory other)
    {
        bool ok;
        (ok, before_) = target.call(first);
        require(ok, "first render failed");
        (ok, other) = target.call(different);
        require(ok, "interleaved render failed");
        (ok,) = target.call(invalid);
        require(!ok, "invalid render succeeded");
        (ok, after_) = target.call(first);
        require(ok, "repeat render failed");
    }
}

/// @dev These properties compare whole outputs after changing just one field.
/// The supplied vector suite remains the independent oracle for the artwork.
/// forge-config: default.fuzz.runs = 512
contract NightWatchRendererPropertiesTest is RendererProbes {
    function testFuzz_labelChangesOnlyItsPlateFragment(
        uint256 number,
        uint8 rawTier,
        uint8[7] memory traits,
        uint16[10] memory inputs,
        uint16 points,
        bytes memory label
    ) public view {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        string memory baseline = renderer.svg(number, tier, traits, "UNIQUE LABEL ANCHOR", inputs, points);
        string memory expected = _replaceOnce(baseline, "UNIQUE LABEL ANCHOR", label);
        assertEq(
            bytes(renderer.svg(number, tier, traits, string(label), inputs, points)),
            bytes(expected),
            "changing a raw label changed other SVG bytes"
        );
    }

    function test_labelNullsInvalidUtf8AndAbiWordBoundaries() public view {
        uint256[10] memory lengths = [uint256(0), 1, 31, 32, 33, 63, 64, 65, 256, 4096];
        for (uint256 i; i < lengths.length; ++i) {
            bytes memory label = new bytes(lengths[i]);
            for (uint256 j; j < label.length; ++j) {
                label[j] = j % 2 == 0 ? bytes1(0) : bytes1(0xff);
            }
            testFuzz_labelChangesOnlyItsPlateFragment(type(uint256).max, 6, _traits(), _inputs(), 65535, label);
        }
        testFuzz_labelChangesOnlyItsPlateFragment(
            0, 4, _traits(), _inputs(), 0, bytes(unicode' </text><g id="&"><![CDATA[夜]]></g>\r\n ')
        );
    }

    function testFuzz_pointsChangeOnlyTheirPlateFragment(uint8 rawTier, uint16 points) public view {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        string memory baseline = renderer.svg(42, tier, _traits(), "LABEL", _inputs(), 0);
        string memory expected =
            _replaceOnce(baseline, ">0 FP</text>", bytes(string.concat(">", vm.toString(points), " FP</text>")));
        assertEq(renderer.svg(42, tier, _traits(), "LABEL", _inputs(), points), expected);
    }

    function testFuzz_sourceNumberChangesOnlyItsOrderedPosition(uint8 rawTier, uint8 rawPosition, uint16 source)
        public
        view
    {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        uint256 position = bound(rawPosition, 0, 9);
        uint16[10] memory inputs = _inputs();
        string memory baseline = renderer.svg(42, tier, _traits(), "LABEL", inputs, 321);
        string memory prefix = position == 0 ? "FORGED FROM #" : " #";
        string memory suffix = position == 9 ? "</text>" : " ";
        string memory expected = _replaceOnce(
            baseline,
            string.concat(prefix, vm.toString(inputs[position]), suffix),
            bytes(string.concat(prefix, vm.toString(source), suffix))
        );
        inputs[position] = source;
        assertEq(renderer.svg(42, tier, _traits(), "LABEL", inputs, 321), expected);
    }

    function test_duplicateAndZeroSourcesAreNotSortedOrDeduplicated() public view {
        uint16[10] memory inputs = [uint16(7), 0, 7, 65535, 1, 0, 7, 65535, 1, 0];
        string memory baseline = _render(6);
        string memory expected = _replaceOnce(
            baseline,
            "FORGED FROM #0 #1 #9 #10 #99 #100 #255 #256 #65534 #65535",
            bytes("FORGED FROM #7 #0 #7 #65535 #1 #0 #7 #65535 #1 #0")
        );
        assertEq(renderer.svg(42, 6, _traits(), "PROBE LABEL", inputs, 321), expected);
    }

    function testFuzz_badgeDependsOnlyOnAccessoryOne(uint256 number, uint8 rawTier, uint8 rawOtherAccessory)
        public
        view
    {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        uint8[7] memory traits = _traits();
        traits[6] = 0;
        string memory baseline = renderer.svg(number, tier, traits, "LABEL", _inputs(), 0);
        traits[6] = uint8(bound(rawOtherAccessory, 2, 255));
        // The probe emits the same layer bytes for every index, so any difference
        // here would be extra renderer logic rather than changed upstream art.
        assertEq(renderer.svg(number, tier, traits, "LABEL", _inputs(), 0), baseline);
        traits[6] = 1;
        string memory expected = _replaceOnce(
            baseline,
            '<probe-layer id="6"/></g>',
            bytes(
                string.concat(
                    '<probe-layer id="6"/></g><text x="500" y="858" font-size="23" fill="#08070D" text-anchor="middle">NW',
                    vm.toString(number),
                    "</text>"
                )
            )
        );
        assertEq(renderer.svg(number, tier, traits, "LABEL", _inputs(), 0), expected);
    }

    function test_badgeAtZeroAndMaximumNumberForEveryTier() public view {
        for (uint8 tier = 1; tier <= 6; ++tier) {
            testFuzz_badgeDependsOnlyOnAccessoryOne(0, tier, 2);
            testFuzz_badgeDependsOnlyOnAccessoryOne(type(uint256).max, tier, 255);
        }
    }

    function testFuzz_sameArgumentsIgnoreCallerAndBlockContext(
        address caller,
        address origin,
        uint64 timestamp,
        uint64 blockNumber,
        uint64 chain,
        uint8 rawTier
    ) public {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        string memory expected = _render(tier);
        vm.warp(timestamp);
        vm.roll(blockNumber);
        vm.chainId(chain);
        bytes memory data = _callData(tier);
        vm.prank(caller, origin);
        (bool ok, bytes memory actual) = address(renderer).call(data);
        assertTrue(ok, "ordinary caller cannot render");
        assertEq(abi.decode(actual, (string)), expected);
    }

    function testFuzz_interleavedRendersAreIndependentWithinOneTransaction(uint8 rawTier, uint8 rawOtherTier) public {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        uint8 otherTier = uint8(bound(rawOtherTier, 1, 5));
        if (otherTier >= tier) ++otherTier;
        string memory expected = _render(tier);
        string memory otherExpected = _render(otherTier);
        RenderSequenceProbe probe = new RenderSequenceProbe();
        (bytes memory before_, bytes memory after_, bytes memory other) =
            probe.renderSequence(address(renderer), _callData(tier), _callData(otherTier), _callData(0));
        assertEq(abi.decode(before_, (string)), expected);
        assertEq(after_, before_, "another render or a revert contaminated this render");
        assertEq(abi.decode(other, (string)), otherExpected);
    }

    function testFuzz_ordinaryCallMakesOnlySpecifiedStaticReads(
        uint256 number,
        uint8 rawTier,
        uint8[7] memory traits,
        uint16 points
    ) public {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        bytes memory data = abi.encodeCall(NightWatchRenderer.svg, (number, tier, traits, "LABEL", _inputs(), points));
        vm.record();
        vm.recordLogs();
        vm.startStateDiffRecording();
        (bool ok, bytes memory actual) = address(renderer).call(data);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(renderer));
        assertTrue(ok, "ordinary zero-value CALL failed");
        assertEq(reads.length, 0, "renderer read storage");
        assertEq(writes.length, 0, "renderer wrote storage");
        assertEq(logs.length, 0, "renderer or dependency emitted a log");
        assertEq(address(renderer).balance, 0);
        bool[9] memory seen;
        uint256 calls;
        for (uint256 i; i < accesses.length; ++i) {
            VmSafe.AccountAccess memory access = accesses[i];
            if (access.accessor != address(renderer) || access.kind == VmSafe.AccountAccessKind.Resume) continue;
            assertEq(uint256(access.kind), uint256(VmSafe.AccountAccessKind.StaticCall), "non-static dependency access");
            assertEq(access.value, 0);
            assertFalse(access.reverted);
            assertEq(access.oldBalance, access.newBalance);
            uint256 slot = 9;
            if (access.account == FROGS) {
                for (uint8 layer; layer < 7; ++layer) {
                    if (
                        keccak256(access.data)
                            == keccak256(abi.encodeCall(INightFrogsRenderer.traitSVG, (layer, traits[layer])))
                    ) {
                        slot = layer;
                        break;
                    }
                }
            } else if (access.account == ART) {
                if (keccak256(access.data) == keccak256(abi.encodeCall(IArtStore.read, (0)))) slot = 7;
                if (tier == 6 && keccak256(access.data) == keccak256(abi.encodeCall(IArtStore.read, (3)))) slot = 8;
            }
            assertLt(slot, 9, "unexpected target or calldata");
            assertFalse(seen[slot], "duplicate dependency call");
            seen[slot] = true;
            ++calls;
        }
        assertEq(calls, tier == 6 ? 9 : 8);
        for (uint256 i; i < 8; ++i) {
            assertTrue(seen[i], "required dependency was not called");
        }
        assertEq(seen[8], tier == 6);
        assertEq(abi.decode(actual, (string)), renderer.svg(number, tier, traits, "LABEL", _inputs(), points));
    }

    function testFuzz_unknownSelectorsAlwaysRevert(bytes4 selector, bytes memory tail) public {
        if (selector == NightWatchRenderer.svg.selector) selector ^= bytes4(uint32(1));
        (bool ok,) = address(renderer).call(abi.encodePacked(selector, tail));
        assertFalse(ok, "unexpected external entry point");
    }

    function testFuzz_anyPositiveValueIsRejected(uint96 amount, uint8 rawTier) public {
        uint256 value = bound(amount, 1, type(uint96).max);
        vm.deal(address(this), value);
        (bool render,) = address(renderer).call{value: value}(_callData(uint8(bound(rawTier, 1, 6))));
        (bool receiveCall,) = address(renderer).call{value: value}("");
        assertFalse(render, "svg accepted value");
        assertFalse(receiveCall, "receive accepted value");
        assertEq(address(renderer).balance, 0);
        assertEq(address(this).balance, value, "failed call retained value");
    }

    function test_constructorRejectsValue() public {
        bytes memory creationCode = type(NightWatchRenderer).creationCode;
        vm.deal(address(this), 1);
        address created;
        assembly ("memory-safe") {
            created := create(1, add(creationCode, 32), mload(creationCode))
        }
        assertEq(created, address(0), "payable constructor accepted ETH");
        assertEq(address(this).balance, 1);
    }

    function test_nonCanonicalNarrowIntegersRevertInsteadOfTruncating() public {
        // ABI words: n, t, traits[0..6], label offset, inputs[0..9], points.
        for (uint256 word = 1; word <= 20; ++word) {
            if (word == 9) continue;
            bytes memory data = _callData(1);
            uint256 value = word < 9 ? 256 : 65536;
            assembly ("memory-safe") {
                mstore(add(add(data, 36), mul(word, 32)), value)
            }
            (bool ok,) = address(renderer).call(data);
            assertFalse(ok, "noncanonical integer was truncated");
        }
    }

    function test_truncatedCalldataAndInvalidLabelOffsetRevert() public {
        bytes memory canonical = _callData(1);
        uint256[5] memory lengths = [uint256(0), 3, 4, 675, 707];
        for (uint256 i; i < lengths.length; ++i) {
            (bool ok,) = address(renderer).call(_slice(canonical, 0, lengths[i]));
            assertFalse(ok, "truncated ABI accepted");
        }
        assembly ("memory-safe") {
            mstore(add(canonical, 324), not(0))
        }
        (bool offsetOk,) = address(renderer).call(canonical);
        assertFalse(offsetOk, "out-of-bounds label offset accepted");
    }
}
