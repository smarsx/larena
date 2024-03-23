// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DeployMain} from "../../script/deploy/DeployMain.s.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

contract DeployPolygonTest is Test {
    DeployMain deployScript;

    function setUp() public {
        vm.setEnv(
            "DEPLOYER_PRIVATE_KEY",
            "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        );
        vm.setEnv(
            "OCMEME_PRIVATE_KEY",
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

        deployScript = new DeployMain();
        deployScript.run();
    }

    /// @notice Test goo addresses where correctly set.
    function testGooAddressCorrectness() public view {
        assertEq(deployScript.goo().ocmeme(), address(deployScript.ocmeme()));
        assertEq(address(deployScript.goo().pages()), address(deployScript.pages()));
    }

    /// @notice Test page addresses where correctly set.
    function testPagesAddressCorrectness() public view {
        assertEq(address(deployScript.pages().ocmeme()), address(deployScript.ocmeme()));
        assertEq(address(deployScript.pages().goo()), address(deployScript.goo()));
    }

    /// @notice Test that ocmeme ownership is correctly transferred to cold wallet.
    function testOcmemeOwnership() public view {
        assertEq(deployScript.ocmeme().owner(), deployScript.coldWallet());
    }

    function testReserveOwnership() public view {
        assertEq(deployScript.reserve().owner(), deployScript.coldWallet());
    }
}
