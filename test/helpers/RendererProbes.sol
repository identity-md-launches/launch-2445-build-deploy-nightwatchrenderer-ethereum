// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightWatchRenderer, INightFrogsRenderer, IArtStore} from "src/NightWatchRenderer.sol";

/// @dev Synthetic artwork, deliberately distinct from the captured mainnet fixture.
/// Index-independent markers let a property isolate the renderer's accessory logic.
/// Argument forwarding is checked separately against recorded call data.
contract ProbeFrogs {
    function traitSVG(uint8 layer, uint8) external pure returns (string memory) {
        require(layer < 7, "unexpected layer");
        return string(abi.encodePacked('<probe-layer id="', bytes1(uint8(48 + layer)), '"/>'));
    }
}

contract ProbeArt {
    function read(uint256 index) external pure returns (string memory) {
        if (index == 0) return "<probe-base/>";
        if (index == 3) return "<probe-captain/>";
        revert("unexpected art index");
    }
}

abstract contract RendererProbes is Test {
    address internal constant FROGS = 0x4D9BfbafE31eC18E9D3066F1475e24906d155D67;
    address internal constant ART = 0x2A0140BC2b117ffEe9b092af1a927b96328FB000;
    NightWatchRenderer internal renderer;

    function setUp() public virtual {
        vm.etch(FROGS, address(new ProbeFrogs()).code);
        vm.etch(ART, address(new ProbeArt()).code);
        renderer = new NightWatchRenderer();
    }

    function _traits() internal pure returns (uint8[7] memory) {
        return [uint8(0), 1, 2, 3, 4, 5, 6];
    }

    function _inputs() internal pure returns (uint16[10] memory) {
        return [uint16(0), 1, 9, 10, 99, 100, 255, 256, 65534, 65535];
    }

    function _callData(uint8 tier) internal pure returns (bytes memory) {
        return abi.encodeCall(NightWatchRenderer.svg, (42, tier, _traits(), "PROBE LABEL", _inputs(), 321));
    }

    function _render(uint8 tier) internal view returns (string memory) {
        return renderer.svg(42, tier, _traits(), "PROBE LABEL", _inputs(), 321);
    }

    /// @dev Slots 0..6 are frog layers, 7 is BASE, and 8 is the Captain overlay.
    function _dependency(uint256 slot) internal pure returns (address target, bytes memory data, string memory marker) {
        if (slot < 7) {
            uint8 layer = uint8(slot);
            return (
                FROGS,
                abi.encodeCall(INightFrogsRenderer.traitSVG, (layer, layer)),
                string(abi.encodePacked('<probe-layer id="', bytes1(uint8(48 + layer)), '"/>'))
            );
        }
        require(slot < 9, "invalid dependency slot");
        return
            (ART, abi.encodeCall(IArtStore.read, (slot == 7 ? 0 : 3)), slot == 7 ? "<probe-base/>" : "<probe-captain/>");
    }

    /// @dev The baseline and needle are ASCII. Copy replacement as opaque bytes:
    /// using a host string replacement could normalize malformed UTF-8 fuzz inputs.
    function _replaceOnce(string memory baseline, string memory needle, bytes memory replacement)
        internal
        pure
        returns (string memory)
    {
        bytes memory source = bytes(baseline);
        uint256 start = vm.indexOf(baseline, needle);
        require(bytes(needle).length > 0 && start != type(uint256).max, "missing test anchor");
        uint256 end = start + bytes(needle).length;
        bytes memory suffix = _slice(source, end, source.length - end);
        require(vm.indexOf(string(suffix), needle) == type(uint256).max, "ambiguous test anchor");
        return string(bytes.concat(_slice(source, 0, start), replacement, suffix));
    }

    function _slice(bytes memory source, uint256 start, uint256 length) internal pure returns (bytes memory result) {
        require(start <= source.length && length <= source.length - start, "test slice out of bounds");
        result = new bytes(length);
        assembly ("memory-safe") {
            mcopy(add(result, 32), add(add(source, 32), start), length)
        }
    }
}
