// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployTestnet} from "../../script/deploy/DeployTestnet.s.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

contract DeployTestnetTest is Test {
    DeployTestnet deployScript;

    function setUp() public {
        vm.setEnv(
            "DEPLOYER_PRIVATE_KEY",
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
        vm.setEnv(
            "LARENA_PRIVATE_KEY",
            "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        );
        vm.setEnv(
            "PAGES_PRIVATE_KEY",
            "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        );
        vm.setEnv(
            "GOO_PRIVATE_KEY",
            "0xdddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
        );

        vm.deal(vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY")), type(uint64).max);

        deployScript = new DeployTestnet();
        deployScript.run();
    }

    /// @notice Test coin addresses where correctly set.
    function testCoinAddressCorrectness() public view {
        assertEq(deployScript.coin().larena(), address(deployScript.larena()));
        assertEq(address(deployScript.coin().pages()), address(deployScript.pages()));
    }

    /// @notice Test page addresses where correctly set.
    function testPagesAddressCorrectness() public view {
        assertEq(address(deployScript.pages().larena()), address(deployScript.larena()));
        assertEq(address(deployScript.pages().coin()), address(deployScript.coin()));
    }

    /// @notice Test that larena ownership is correctly transferred to cold wallet.
    function testLarenaOwnership() public view {
        assertEq(deployScript.larena().owner(), deployScript.coldWallet());
    }

    function testReserveOwnership() public view {
        assertEq(deployScript.reserve().owner(), deployScript.coldWallet());
    }
}
