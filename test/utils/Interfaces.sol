// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ocmeme} from "../../src/Ocmeme.sol";

contract Interfaces {
    function getEpochs(uint256 _epochID, Ocmeme _ocmeme) public view returns (Ocmeme.Epoch memory) {
        (
            uint8 claims,
            uint16 firstTokenID,
            uint32 goldPageID,
            uint32 silverPageID,
            uint32 bronzePageID,
            uint136 proceeds
        ) = _ocmeme.$epochs(_epochID);
        return
            Ocmeme.Epoch({
                claims: claims,
                firstTokenID: firstTokenID,
                goldPageID: goldPageID,
                silverPageID: silverPageID,
                bronzePageID: bronzePageID,
                proceeds: proceeds
            });
    }

    function getVotes(uint256 _pageID, Ocmeme _ocmeme) public view returns (Ocmeme.Vote memory) {
        (uint40 epochEnd, uint216 votes) = _ocmeme.$votes(_pageID);
        return Ocmeme.Vote({epochEnd: epochEnd, votes: votes});
    }
}
