// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MainnetFixture} from "./helpers/MainnetFixture.sol";

contract NightWatchRendererVectorsTest is MainnetFixture {
    function setUp() public {
        _loadMainnet();
    }

    function test_vectorShiftLead() public view {
        _check(0, 0x6c9b4ba9e1d970ae878562252ecde4ba26c461fec4cc1af9d983049fcccbb448);
    }

    function test_vectorForeman() public view {
        _check(1, 0x6599cac260892032e955386e9d89eadb3155873df88c7d0eb9811d0516a71e9f);
    }

    function test_vectorSupervisor() public view {
        _check(2, 0x77a2bd2785100118716ecfd64d45fac8dc442da9985103657651e4cdfd3cff34);
    }

    function test_vectorKodes() public view {
        _check(3, 0x7615dc42aa811e30e90ea4b235d71d4fdf31c0fa8e07440ee34715e47fd00609);
    }

    function test_vectorCaptain() public view {
        _check(4, 0xe3bc253ef478a52132f479126df379e37100408b505528a7fee1b5879cf27cdc);
    }

    function test_snapshotReproducesEveryCapturedCall() public view {
        string memory snapshot = vm.readFile("test/fixtures/mainnet.json");
        uint256 count = vm.parseJsonArrayLength(snapshot, ".calls");
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".calls[", vm.toString(i), "]");
            address target = vm.parseJsonAddress(snapshot, string.concat(key, ".to"));
            bytes memory data = vm.parseJsonBytes(snapshot, string.concat(key, ".data"));
            bytes memory expected = vm.parseJsonBytes(snapshot, string.concat(key, ".result"));
            (bool ok, bytes memory actual) = target.staticcall(data);
            assertTrue(ok, "snapshot dependency call failed");
            assertEq(actual, expected, "snapshot dependency response differs from mainnet");
        }
    }

    function test_gasShiftLeadCold() public {
        _measure(0);
    }

    function test_gasForemanCold() public {
        _measure(1);
    }

    function test_gasSupervisorCold() public {
        _measure(2);
    }

    function test_gasKodesCold() public {
        _measure(3);
    }

    function test_gasCaptainCold() public {
        _measure(4);
    }

    function _measure(uint256 index) private {
        Vector memory v = _vector(index);
        for (uint256 j; j < dependencyAccounts.length; ++j) {
            vm.cool(dependencyAccounts[j]);
        }
        vm.cool(address(renderer));
        uint256 start = gasleft();
        string memory result = _render(v);
        uint256 used = start - gasleft();
        emit log_named_uint(v.name, used);
        assertEq(keccak256(bytes(result)), v.hash);
        assertLt(used, 1_000_000, "unexpected rendering gas regression");
    }

    function _check(uint256 index, bytes32 expected) private view {
        Vector memory v = _vector(index);
        assertEq(v.hash, expected, "fixture vector hash was changed");
        string memory actual = _render(v);
        assertEq(keccak256(bytes(actual)), expected);
        assertEq(actual, vm.readFile(string.concat("docs/images/", v.name, ".svg")), "README image differs");
    }
}
