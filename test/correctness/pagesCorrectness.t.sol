// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Ocmeme} from "../../src/Ocmeme.sol";
import {Coin} from "../../src/Coin.sol";
import {Pages} from "../../src/Pages.sol";

contract PagesCorrectnessTest is DSTestPlus {
    using LibString for uint256;

    uint256 internal immutable TWENTY_YEARS = 7300 days;

    int256 internal immutable INITIAL_PRICE = .0042069e18;

    int256 internal immutable PER_PERIOD_PRICE_DECREASE = 0.31e18;

    int256 internal immutable PER_PERIOD = 4e18;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Pages internal pages;

    function setUp() public {
        pages = new Pages(block.timestamp, Coin(address(0)), address(0), Ocmeme(address(0)));
    }

    function testFFICorrectness(uint256 timeSinceStart, uint256 numSold) public {
        numSold = bound(numSold, 0, 10000);

        timeSinceStart = bound(timeSinceStart, 0, TWENTY_YEARS);

        try pages.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), numSold) returns (
            uint256 actualPrice
        ) {
            // Calc expected price from py script
            uint256 expectedPrice = calculatePrice(
                timeSinceStart,
                numSold + 1,
                INITIAL_PRICE,
                PER_PERIOD_PRICE_DECREASE,
                PER_PERIOD
            );

            if (expectedPrice < 0.0000000000001e18) return; // For really small prices we can't expect them to be equal.

            // Equal within 1 percent.
            assertRelApproxEq(actualPrice, expectedPrice, 0.01e18);
        } catch {
            // If it reverts that's fine, there are some bounds on the function, they are tested in VRGDAs.t.sol
        }
    }

    function calculatePrice(
        uint256 _timeSinceStart,
        uint256 _numSold,
        int256 _targetPrice,
        int256 _PER_PERIOD_PRICE_DECREASE,
        int256 _PER_PERIOD
    ) private returns (uint256) {
        string[] memory inputs = new string[](13);
        inputs[0] = "python3";
        inputs[1] = "analysis/compute_price.py";
        inputs[2] = "pages";
        inputs[3] = "--time_since_start";
        inputs[4] = _timeSinceStart.toString();
        inputs[5] = "--num_sold";
        inputs[6] = _numSold.toString();
        inputs[7] = "--initial_price";
        inputs[8] = uint256(_targetPrice).toString();
        inputs[9] = "--per_period_price_decrease";
        inputs[10] = uint256(_PER_PERIOD_PRICE_DECREASE).toString();
        inputs[11] = "--per_period_post_switchover";
        inputs[12] = uint256(_PER_PERIOD).toString();

        return abi.decode(vm.ffi(inputs), (uint256));
    }
}
