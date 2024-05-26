// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {Larena} from "../../src/Larena.sol";
import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {console2 as console} from "forge-std/console2.sol";

import {Coin} from "../../src/Coin.sol";
import {Pages} from "../../src/Pages.sol";
import {Unrevealed} from "../../src/utils/Unrevealed.sol";

contract LarenaCorrectnessTest is DSTestPlus {
    using LibString for uint256;

    uint256 internal immutable TWENTY_YEARS = 7300 days;

    uint256 internal MAX_MINTABLE = 10000;

    int256 internal LOGISTIC_SCALE;

    int256 internal immutable INITIAL_PRICE = .0125e18;

    int256 internal immutable PER_PERIOD_PRICE_DECREASE = 0.31e18;

    int256 internal immutable TIME_SCALE = 0.0138e18;
    int256 internal immutable SWITCHOVER_TIME = 1230e18;
    int256 internal immutable PER_PERIOD_POST_SWITCHOVER = 10e18;

    Vm internal immutable vm = Vm(HEVM_ADDRESS);

    Larena internal larena;

    function setUp() public {
        larena = new Larena(
            Coin(address(0)),
            Pages(address(0)),
            Unrevealed(address(0)),
            address(0)
        );
        LOGISTIC_SCALE = int256((MAX_MINTABLE + 1) * 2e18);
    }

    function testFFICorrectness(uint256 timeSinceStart, uint256 numSold) public {
        // Limit num sold to max mint.
        numSold = bound(numSold, 0, MAX_MINTABLE - 1);

        // Limit mint time to 20 years.
        timeSinceStart = bound(timeSinceStart, 0, TWENTY_YEARS);

        // Calculate actual price from VRGDA.
        try larena.getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), numSold) returns (
            uint256 actualPrice
        ) {
            // Calculate expected price from python script.
            uint256 expectedPrice = calculatePrice(
                timeSinceStart,
                numSold + 1,
                INITIAL_PRICE,
                PER_PERIOD_PRICE_DECREASE,
                LOGISTIC_SCALE,
                TIME_SCALE,
                PER_PERIOD_POST_SWITCHOVER,
                SWITCHOVER_TIME
            );

            if (expectedPrice < 0.0000000000001e18) return; // For really small prices we can't expect them to be equal.

            assertRelApproxEq(actualPrice, expectedPrice, 0.01e18);
        } catch {
            // If it reverts that's fine, there are some bounds on the function, they are tested in VRGDAs.t.sol
        }
    }

    function calculatePrice(
        uint256 _timeSinceStart,
        uint256 _numSold,
        int256 _targetPrice,
        int256 _perPeriodPriceDecrease,
        int256 _logisticScale,
        int256 _timeScale,
        int256 _perPeriodPostSwitchover,
        int256 _switchoverTime
    ) private returns (uint256) {
        string[] memory inputs = new string[](19);
        inputs[0] = "python3";
        inputs[1] = "analysis/compute_price.py";
        inputs[2] = "larena";
        inputs[3] = "--time_since_start";
        inputs[4] = _timeSinceStart.toString();
        inputs[5] = "--num_sold";
        inputs[6] = _numSold.toString();
        inputs[7] = "--initial_price";
        inputs[8] = uint256(_targetPrice).toString();
        inputs[9] = "--per_period_price_decrease";
        inputs[10] = uint256(_perPeriodPriceDecrease).toString();
        inputs[11] = "--logistic_scale";
        inputs[12] = uint256(_logisticScale).toString();
        inputs[13] = "--time_scale";
        inputs[14] = uint256(_timeScale).toString();
        inputs[15] = "--per_period_post_switchover";
        inputs[16] = uint256(_perPeriodPostSwitchover).toString();
        inputs[17] = "--switchover_time";
        inputs[18] = uint256(_switchoverTime).toString();

        return abi.decode(vm.ffi(inputs), (uint256));
    }
}
