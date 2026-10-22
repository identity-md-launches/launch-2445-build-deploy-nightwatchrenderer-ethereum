// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {NightWatchRenderer, INightFrogsRenderer, IArtStore} from "../src/NightWatchRenderer.sol";

// Test doubles make ordering and byte preservation visible independently of the real artwork.
contract MarkedFrogs {
    function traitSVG(uint8 layer, uint8 index) external pure returns (string memory) {
        return string(abi.encodePacked("LAYER[", bytes1(layer), bytes1(index), "]"));
    }
}

contract MarkedArt {
    function read(uint256 index) external pure returns (string memory) {
        if (index == 0) return "<base/>";
        if (index == 3) return "<captain/>";
        revert("unexpected art index");
    }
}

// Deliberately non-view to check that the renderer enforces STATICCALL at the EVM level.
contract WritingArt {
    uint256 private calls;

    function read(uint256) external returns (string memory) {
        ++calls;
        return "<write/>";
    }
}

contract NightWatchRendererTest is Test {
    address private constant FROGS = 0x4D9BfbafE31eC18E9D3066F1475e24906d155D67;
    address private constant ART = 0x2A0140BC2b117ffEe9b092af1a927b96328FB000;
    NightWatchRenderer private renderer;
    uint8[7] private traits = [4, 2, 4, 3, 1, 5, 5];
    uint16[10] private inputs = [184, 185, 186, 189, 190, 78, 80, 81, 82, 86];

    function setUp() public {
        vm.etch(FROGS, address(new MarkedFrogs()).code);
        vm.etch(ART, address(new MarkedArt()).code);
        renderer = new NightWatchRenderer();
    }

    function test_zeroTierRevertsBeforeDependencyCalls() public {
        _checkInvalidTier(0);
    }

    function test_sevenTierRevertsBeforeDependencyCalls() public {
        _checkInvalidTier(7);
    }

    function testFuzz_allOtherTiersRevert(uint8 tier) public {
        vm.assume(tier == 0 || tier > 6);
        _checkInvalidTier(tier);
    }

    function test_tierFourAndAllThresholds() public view {
        string[6] memory colors = ["#3FE6FF", "#B8FF4A", "#A98BFF", "#FF4FD8", "#FFC46B", "#E9E4FF"];
        string[6] memory romans = ["I", "II", "III", "IV", "V", "C"];
        string[6] memory light = [".6", ".7", ".8", ".9", "1", "1"];
        for (uint8 tier = 1; tier <= 6; ++tier) {
            string memory result = renderer.svg(1, tier, traits, "LABEL", inputs, 10);
            _contains(result, string.concat('height="1000" color="', colors[tier - 1], '"><title>'));
            _contains(result, string.concat('r="480" fill="url(#otL)" opacity="', light[tier - 1], '"/>'));
            _contains(result, string.concat("NIGHTSHIFT / NIGHT WATCH / TIER ", romans[tier - 1], "</text>"));
            assertEq(_count(result, 'stroke-dasharray="8 44"'), tier >= 2 ? 1 : 0, "rays threshold");
            if (tier >= 2) {
                _contains(result, string.concat('opacity="', tier <= 3 ? ".22" : ".34", '" mask="url(#otM)">'));
            }
            assertEq(_count(result, 'r="402"'), tier >= 3 ? 1 : 0, "ring threshold");
            assertEq(_count(result, 'r="432"'), tier >= 5 ? 1 : 0, "second ring threshold");
            assertEq(_count(result, 'type="rotate"'), tier >= 5 ? 3 : 0, "rotation threshold");
            assertEq(_count(result, 'values="0 0;0 -280"'), tier >= 3 ? 4 * uint256(tier) - 6 : 0, "embers");
            assertEq(_count(result, "mix-blend-mode:overlay"), tier >= 4 ? 1 : 0, "hologram threshold");
            assertEq(_count(result, "M72 36H928"), tier >= 2 ? 1 : 0, "inner frame threshold");
            assertEq(_count(result, 'values=".15;.7;.15"'), tier >= 4 ? 1 : 0, "pulse threshold");
            assertEq(_count(result, "M436 44L448"), tier >= 5 ? 1 : 0, "boss threshold");
            assertEq(_count(result, "<captain/>"), tier == 6 ? 1 : 0, "captain art threshold");
            assertEq(_count(result, '<g filter="url(#otE)">'), tier >= 3 ? 2 : 0, "eye and embers groups");
            _contains(
                result,
                string.concat(
                    'M884 50L936 80V140L884 170L832 140V80Z" fill="',
                    tier >= 4 ? "currentColor" : "#08070D",
                    '" stroke="currentColor" stroke-width="5"/><text x="884" y="126" font-size="',
                    tier == 3 ? "34" : "40",
                    '" fill="',
                    tier >= 4 ? "#08070D" : "currentColor",
                    '" text-anchor="middle">',
                    romans[tier - 1],
                    "</text>"
                )
            );
            for (uint256 k; k < 5; ++k) {
                _contains(
                    result,
                    string.concat(
                        '<rect x="',
                        vm.toString(66 + 34 * k),
                        '" y="158" width="26" height="8" fill="currentColor" opacity="',
                        k < tier ? "1" : ".2",
                        '"/>'
                    )
                );
            }
        }
    }

    function test_emberEndpointsAndSpinDurations() public view {
        string memory result = renderer.svg(0, 6, traits, "", inputs, 0);
        _contains(result, '<circle cx="110" cy="560" r="4" fill="currentColor">');
        _contains(
            result,
            '<circle cx="861" cy="611" r="8" fill="currentColor"><animateTransform attributeName="transform" type="translate" values="0 0;0 -280" dur="5s" repeatCount="indefinite"/><animate attributeName="opacity" values="0;1;0" dur="5s" repeatCount="indefinite"/></circle></g>'
        );
        _contains(result, 'to="360 500 540" dur="80s"');
        _contains(result, 'to="360 500 540" dur="120s"');
        _contains(result, 'to="-360 500 540" dur="90s"');
    }

    function test_badgeForAccessoryOneOnly() public view {
        uint8[7] memory selection = traits;
        selection[6] = 1;
        string memory result = renderer.svg(987, 1, selection, "", inputs, 0);
        _contains(result, '</g><text x="500" y="858" font-size="23" fill="#08070D" text-anchor="middle">NW987</text>');
        selection[6] = 0;
        assertEq(_count(renderer.svg(987, 6, selection, "", inputs, 0), ">NW987</text>"), 0);
        selection[6] = 2;
        assertEq(_count(renderer.svg(987, 2, selection, "", inputs, 0), ">NW987</text>"), 0);
    }

    function test_layersAndOverlaysInExactOrder() public view {
        uint8[7] memory selection = traits;
        selection[6] = 1;
        string memory result = renderer.svg(1, 6, selection, "", inputs, 0);
        uint256 cursor = _after(result, "<base/>", 0);
        cursor = _after(result, "<defs>", cursor);
        cursor = _after(result, _layer(0, selection[0]), cursor);
        cursor = _after(result, 'r="480"', cursor);
        cursor = _after(result, 'r="330"', cursor);
        cursor = _after(result, 'r="402"', cursor);
        cursor = _after(result, 'r="432"', cursor);
        cursor = _after(result, '<g filter="url(#otA)">', cursor);
        for (uint8 i = 1; i < 7; ++i) {
            if (i == 4) cursor = _after(result, '<g filter="url(#otE)">', cursor);
            cursor = _after(result, _layer(i, selection[i]), cursor);
            if (i == 4) cursor = _after(result, "</g>", cursor);
        }
        cursor = _after(result, "</g>", cursor);
        cursor = _after(result, ">NW1</text>", cursor);
        cursor = _after(result, "<captain/>", cursor);
        cursor = _after(result, 'values="0 0;0 -280"', cursor);
        cursor = _after(result, "mix-blend-mode:overlay", cursor);
        cursor = _after(result, 'fill="url(#vignette)"', cursor);
        cursor = _after(result, "M60 24H940", cursor);
        cursor = _after(result, "M72 36H928", cursor);
        cursor = _after(result, 'values=".15;.7;.15"', cursor);
        cursor = _after(result, "M436 44L448", cursor);
        cursor = _after(result, ">NIGHT WATCHER</text>", cursor);
        cursor = _after(result, 'y="158"', cursor);
        cursor = _after(result, "M884 50L936", cursor);
        cursor = _after(result, "NIGHTSHIFT / NIGHT WATCH / TIER", cursor);
        cursor = _after(result, "M64 870H904", cursor);
        cursor = _after(result, "</svg>", cursor);
        assertEq(cursor, bytes(result).length);
    }

    function testFuzz_traitsForwardedOnce(uint8[7] memory selection, uint8 rawTier) public {
        uint8 tier = uint8(bound(rawTier, 1, 6));
        for (uint8 i; i < 7; ++i) {
            vm.expectCall(FROGS, abi.encodeCall(INightFrogsRenderer.traitSVG, (i, selection[i])), 1);
        }
        vm.expectCall(ART, abi.encodeCall(IArtStore.read, (0)), 1);
        vm.expectCall(ART, abi.encodeCall(IArtStore.read, (3)), tier == 6 ? 1 : 0);
        string memory result = renderer.svg(1, tier, selection, "LABEL", inputs, 0);
        for (uint8 i; i < 7; ++i) {
            assertEq(_count(result, _layer(i, selection[i])), 1);
        }
    }

    function testFuzz_numbersAndRawLabel(uint256 number, uint16[10] memory sources, uint16 points, string memory label)
        public
        view
    {
        string memory result = renderer.svg(number, 1, traits, label, sources, points);
        string memory decimal = vm.toString(number);
        _contains(result, string.concat("<title>NIGHT WATCHERS #", decimal, "</title>"));
        _contains(
            result,
            string.concat(
                'fill="#F2EFFF">#',
                decimal,
                '</text><text x="',
                vm.toString(130 + 20 * bytes(decimal).length),
                '" y="916" font-size="22" fill="currentColor">',
                label,
                '</text><text x="896" y="916" font-size="18" fill="#C4B4FF" text-anchor="end">',
                vm.toString(points),
                " FP</text>"
            )
        );
        string memory expected = "FORGED FROM";
        for (uint256 i; i < 10; ++i) {
            expected = string.concat(expected, " #", vm.toString(sources[i]));
        }
        _contains(result, string.concat(expected, "</text></svg>"));
    }

    function test_zeroMaximumAndDigitBoundaries() public view {
        uint256[8] memory numbers = [uint256(0), 1, 9, 10, 99, 100, 10 ** 77, type(uint256).max];
        uint16[10] memory sources;
        for (uint256 i; i < 10; ++i) {
            sources[i] = type(uint16).max;
        }
        for (uint256 i; i < numbers.length; ++i) {
            testFuzz_numbersAndRawLabel(numbers[i], sources, type(uint16).max, unicode'<tag a="&">\n夜</tag>');
        }
        testFuzz_numbersAndRawLabel(0, inputs, 0, "");
    }

    function testFuzz_anyCallerSameResult(address caller) public {
        string memory expected = renderer.svg(1, 1, traits, "LABEL", inputs, 10);
        vm.prank(caller);
        assertEq(renderer.svg(1, 1, traits, "LABEL", inputs, 10), expected);
    }

    function test_constructorNeedsNoDependencies() public {
        vm.etch(ART, "");
        vm.etch(FROGS, "");
        NightWatchRenderer fresh = new NightWatchRenderer();
        assertGt(address(fresh).code.length, 0);
        assertLe(address(fresh).code.length, 24_576);
        assertEq(address(fresh).balance, 0);
    }

    function test_onlyStaticDependencyCallsAndNoStorageAccess() public {
        vm.record();
        vm.startStateDiffRecording();
        renderer.svg(1, 6, traits, "", inputs, 0);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(address(renderer));
        assertEq(reads.length, 0);
        assertEq(writes.length, 0);
        uint256 dependencyCalls;
        for (uint256 i; i < accesses.length; ++i) {
            VmSafe.AccountAccess memory access = accesses[i];
            if (access.accessor == address(renderer) && access.kind != VmSafe.AccountAccessKind.Resume) {
                assertEq(uint256(access.kind), uint256(VmSafe.AccountAccessKind.StaticCall));
                assertTrue(access.account == FROGS || access.account == ART);
                assertEq(access.value, 0);
                ++dependencyCalls;
            }
        }
        assertEq(dependencyCalls, 9);
    }

    function test_dependencyCannotWriteStorage() public {
        vm.etch(ART, address(new WritingArt()).code);
        // Limit gas forwarded to the deliberately invalid SSTORE in a static context.
        (bool ok,) = address(renderer).staticcall{gas: 1_000_000}(_callData());
        assertFalse(ok);
        assertEq(vm.load(ART, bytes32(0)), bytes32(0));
    }

    function test_dependencyRevertBubbles() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "art unavailable");
        vm.mockCallRevert(ART, abi.encodeCall(IArtStore.read, (0)), reason);
        vm.expectRevert(reason);
        renderer.svg(1, 1, traits, "", inputs, 0);
    }

    function test_traitRevertBubbles() public {
        bytes memory reason = abi.encodeWithSignature("Error(string)", "trait unavailable");
        vm.mockCallRevert(FROGS, abi.encodeCall(INightFrogsRenderer.traitSVG, (4, traits[4])), reason);
        vm.expectRevert(reason);
        renderer.svg(1, 1, traits, "", inputs, 0);
    }

    function test_missingDependencyReverts() public {
        vm.etch(ART, "");
        vm.expectRevert();
        renderer.svg(1, 1, traits, "", inputs, 0);
    }

    function test_malformedDependencyResponseReverts() public {
        vm.mockCall(ART, abi.encodeCall(IArtStore.read, (0)), hex"01");
        vm.expectRevert();
        renderer.svg(1, 1, traits, "", inputs, 0);
    }

    function test_noReceiveFallbackOrAdministration() public {
        (bool empty,) = address(renderer).call("");
        (bool unknown,) = address(renderer).call(hex"ffffffff");
        (bool owner,) = address(renderer).call(abi.encodeWithSignature("owner()"));
        (bool pause,) = address(renderer).call(abi.encodeWithSignature("pause()"));
        assertFalse(empty);
        assertFalse(unknown);
        assertFalse(owner);
        assertFalse(pause);
    }

    function test_rejectsEthWithAndWithoutCalldata() public {
        vm.deal(address(this), 2 wei);
        (bool transfer,) = address(renderer).call{value: 1 wei}("");
        (bool render,) = address(renderer).call{value: 1 wei}(_callData());
        assertFalse(transfer);
        assertFalse(render);
        assertEq(address(renderer).balance, 0);
    }

    function _checkInvalidTier(uint8 tier) private {
        vm.etch(ART, "");
        vm.etch(FROGS, "");
        vm.expectRevert(abi.encodeWithSelector(NightWatchRenderer.InvalidTier.selector, tier));
        renderer.svg(1, tier, traits, "", inputs, 0);
    }

    function _callData() private view returns (bytes memory) {
        return abi.encodeCall(NightWatchRenderer.svg, (1, 1, traits, "", inputs, 0));
    }

    function _layer(uint8 layer, uint8 index) private pure returns (string memory) {
        return string(abi.encodePacked("LAYER[", bytes1(layer), bytes1(index), "]"));
    }

    function _contains(string memory text, string memory fragment) private pure {
        _after(text, fragment, 0);
    }

    function _after(string memory text, string memory fragment, uint256 start) private pure returns (uint256) {
        bytes memory haystack = bytes(text);
        bytes memory needle = bytes(fragment);
        for (uint256 i = start; i + needle.length <= haystack.length; ++i) {
            if (haystack[i] != needle[0]) continue;
            uint256 j = 1;
            while (j < needle.length && haystack[i + j] == needle[j]) ++j;
            if (j == needle.length) return i + j;
        }
        revert(string.concat("missing fragment: ", fragment));
    }

    function _count(string memory text, string memory fragment) private pure returns (uint256 result) {
        bytes memory haystack = bytes(text);
        bytes memory needle = bytes(fragment);
        for (uint256 i; i + needle.length <= haystack.length; ++i) {
            if (haystack[i] != needle[0]) continue;
            uint256 j = 1;
            while (j < needle.length && haystack[i + j] == needle[j]) ++j;
            if (j == needle.length) ++result;
        }
    }
}
