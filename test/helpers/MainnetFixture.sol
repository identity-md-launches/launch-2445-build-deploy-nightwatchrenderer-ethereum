// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {NightWatchRenderer} from "../../src/NightWatchRenderer.sol";

/// @dev Offline execution of captured Ethereum bytecode, including the artwork data contracts.
abstract contract MainnetFixture is Test {
    struct Vector {
        string name;
        uint256 number;
        uint8 tier;
        uint8[7] traits;
        string label;
        uint16[10] inputs;
        uint16 points;
        bytes32 hash;
    }

    NightWatchRenderer internal renderer;
    address[] internal dependencyAccounts;

    function _loadMainnet() internal {
        string memory snapshot = vm.readFile("test/fixtures/mainnet.json");
        assertEq(vm.parseJsonUint(snapshot, ".chainId"), 1);
        vm.chainId(1);
        vm.roll(vm.parseJsonUint(snapshot, ".blockNumber"));
        vm.warp(vm.parseJsonUint(snapshot, ".blockTimestamp"));
        uint256 count = vm.parseJsonArrayLength(snapshot, ".accounts");
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".accounts[", vm.toString(i), "]");
            address account = vm.parseJsonAddress(snapshot, string.concat(key, ".account"));
            vm.etch(account, vm.parseJsonBytes(snapshot, string.concat(key, ".code")));
            dependencyAccounts.push(account);
            uint256 slots = vm.parseJsonArrayLength(snapshot, string.concat(key, ".slots"));
            for (uint256 j; j < slots; ++j) {
                string memory slotKey = string.concat(key, ".slots[", vm.toString(j), "]");
                vm.store(
                    account,
                    vm.parseJsonBytes32(snapshot, string.concat(slotKey, ".slot")),
                    vm.parseJsonBytes32(snapshot, string.concat(slotKey, ".value"))
                );
            }
        }
        renderer = new NightWatchRenderer();
    }

    function _vector(uint256 index) internal view returns (Vector memory v) {
        string memory json = vm.readFile("test/fixtures/vectors.json");
        string memory key = string.concat(".[", vm.toString(index), "]");
        v.name = vm.parseJsonString(json, string.concat(key, ".name"));
        v.number = vm.parseJsonUint(json, string.concat(key, ".n"));
        v.tier = uint8(vm.parseJsonUint(json, string.concat(key, ".t")));
        v.label = vm.parseJsonString(json, string.concat(key, ".label"));
        v.points = uint16(vm.parseJsonUint(json, string.concat(key, ".points")));
        v.hash = vm.parseJsonBytes32(json, string.concat(key, ".hash"));
        uint256[] memory traits = vm.parseJsonUintArray(json, string.concat(key, ".traits"));
        uint256[] memory inputs = vm.parseJsonUintArray(json, string.concat(key, ".inputs"));
        assertEq(traits.length, 7);
        assertEq(inputs.length, 10);
        for (uint256 i; i < 7; ++i) {
            assertLe(traits[i], type(uint8).max);
            v.traits[i] = uint8(traits[i]);
        }
        for (uint256 i; i < 10; ++i) {
            assertLe(inputs[i], type(uint16).max);
            v.inputs[i] = uint16(inputs[i]);
        }
    }

    function _render(Vector memory v) internal view returns (string memory) {
        return renderer.svg(v.number, v.tier, v.traits, v.label, v.inputs, v.points);
    }
}
