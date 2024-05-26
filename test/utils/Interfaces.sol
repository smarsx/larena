// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Larena} from "../../src/Larena.sol";

contract Interfaces {
    function getEpochs(uint256 _epochID, Larena _larena) public view returns (Larena.Epoch memory) {
        (
            uint8 claims,
            uint16 firstTokenID,
            uint32 goldPageID,
            uint32 silverPageID,
            uint32 bronzePageID,
            uint136 proceeds
        ) = _larena.$epochs(_epochID);
        return
            Larena.Epoch({
                claims: claims,
                firstTokenID: firstTokenID,
                goldPageID: goldPageID,
                silverPageID: silverPageID,
                bronzePageID: bronzePageID,
                proceeds: proceeds
            });
    }

    function getVotes(uint256 _pageID, Larena _larena) public view returns (Larena.Vote memory) {
        (uint40 epochEnd, uint216 votes) = _larena.$votes(_pageID);
        return Larena.Vote({epochEnd: epochEnd, votes: votes});
    }

    function getVaultSupply(
        uint256 _epochID,
        uint256 _initial,
        uint256 _fixed,
        uint256 _switch
    ) public pure returns (uint256) {
        unchecked {
            return _epochID > _switch ? _fixed : _initial - _epochID;
        }
    }
}
