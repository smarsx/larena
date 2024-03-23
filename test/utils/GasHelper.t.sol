// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract GasHelpers {
    event log_gas(string, uint256);

    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual returns (uint256) {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        // emit log_gas(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
        return gasDelta;
    }
}
