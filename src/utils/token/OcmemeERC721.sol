// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

/// @notice ERC721 implementation optimized for ocmeme by packing balanceOf/ownerOf with user/attribute data.
/// @author smarsx @_smarsx
/// @author Modified from Art-Gobblers. (https://github.com/artgobblers/art-gobblers/blob/master/src/utils/token/GobblersERC721.sol)
/// @author Modified from Solmate. (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract OcmemeERC721 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /*//////////////////////////////////////////////////////////////
                         METADATA STORAGE/LOGIC
    //////////////////////////////////////////////////////////////*/

    string public name;

    string public symbol;

    function tokenURI(uint256 id) external view virtual returns (string memory);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of ocmemes allowed to be minted to vault.
    uint256 public constant VAULT_NUM = 10;

    /*//////////////////////////////////////////////////////////////
                            Ocmeme/ERC721 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct holding ocmeme data.
    struct MemeData {
        // Order in respective epoch.
        uint32 index;
        // Multiple on goo issuance.
        uint32 emissionMultiple;
        // Epoch ocmeme belongs to.
        uint32 epochID;
        // The current owner of the meme.
        address owner;
    }

    /// @notice Struct holding data relevant to each user's account.
    struct UserData {
        // The total number of ocmemes currently owned by the user.
        uint32 memesOwned;
        // The sum of the multiples of all ocmemes the user holds.
        uint32 emissionMultiple;
        // Timestamp of the last goo balance checkpoint.
        uint64 lastTimestamp;
        // User's goo balance at time of last checkpointing.
        uint128 lastBalance;
    }

    /// @notice Maps ocmeme ids to their data.
    mapping(uint256 => MemeData) public getMemeData;
    /// @notice Maps user addresses to their account data.
    mapping(address => UserData) public getUserData;

    function ownerOf(uint256 id) external view returns (address owner) {
        require((owner = getMemeData[id].owner) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return getUserData[owner].memesOwned;
    }

    /*//////////////////////////////////////////////////////////////
                         ERC721 APPROVAL STORAGE
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => address) public getApproved;

    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 id) external {
        address owner = getMemeData[id].owner;

        require(msg.sender == owner || isApprovedForAll[owner][msg.sender], "NOT_AUTHORIZED");

        getApproved[id] = spender;

        emit Approval(owner, spender, id);
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function transferFrom(address from, address to, uint256 id) public virtual;

    function safeTransferFrom(address from, address to, uint256 id) external {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata data) external {
        transferFrom(from, to, id);

        require(
            to.code.length == 0 ||
                ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
                ERC721TokenReceiver.onERC721Received.selector,
            "UNSAFE_RECIPIENT"
        );
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165 Interface ID for ERC165
            interfaceId == 0x80ac58cd || // ERC165 Interface ID for ERC721
            interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL MINT LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id, uint256 epochID, uint256 index) internal {
        // Does not check if the token was already minted or the recipient is address(0)
        // because Ocmeme.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to msg.sender who cannot be zero.

        // set emission multiple
        uint256 multiple = 7; // beyond 20000

        // The branchless expression below is equivalent to:
        // if (id <= 6896) newCurrentIdMultiple = 2;
        // else if (id <= 11494) newCurrentIdMultiple = 3;
        // else if (id <= 14942) newCurrentIdMultiple = 4;
        // else if (id <= 17701) newCurrentIdMultiple = 5;
        // else if (id <= 20000) newCurrentIdMultiple = 6;

        assembly {
            // prettier-ignore
            multiple := sub(sub(sub(sub(sub(
                multiple,
                lt(id, 20001)),
                lt(id, 17702)),
                lt(id, 14943)),
                lt(id, 11495)),
                lt(id, 6897)
            )
        }

        getMemeData[id].owner = to;
        getMemeData[id].index = uint32(index);
        getMemeData[id].epochID = uint32(epochID);
        getMemeData[id].emissionMultiple = uint32(multiple);

        unchecked {
            ++getUserData[to].memesOwned;
            getUserData[to].emissionMultiple += uint32(multiple);
        }

        emit Transfer(address(0), to, id);
    }

    function _batchMint(
        address to,
        uint256 id,
        uint256 epochID,
        uint256 index
    ) internal returns (uint256) {
        // Does not check if the token was already minted or the recipient is address(0)
        // because Ocmeme.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to owner who cannot be zero.

        // set emission multiple
        uint256 multiple = 7; // beyond 20000

        // The branchless expression below is equivalent to:
        // if (id <= 6896) newCurrentIdMultiple = 2;
        // else if (id <= 11494) newCurrentIdMultiple = 3;
        // else if (id <= 14942) newCurrentIdMultiple = 4;
        // else if (id <= 17701) newCurrentIdMultiple = 5;
        // else if (id <= 20000) newCurrentIdMultiple = 6;

        assembly {
            // prettier-ignore
            multiple := sub(sub(sub(sub(sub(
                multiple,
                lt(id, 20001)),
                lt(id, 17702)),
                lt(id, 14943)),
                lt(id, 11495)),
                lt(id, 6897)
            )
        }

        unchecked {
            getUserData[to].memesOwned += uint32(VAULT_NUM);
            getUserData[to].emissionMultiple += uint32(multiple * VAULT_NUM);

            for (uint256 i = 0; i < VAULT_NUM; ++i) {
                getMemeData[++id].owner = to;
                getMemeData[id].index = uint32(index + i);
                getMemeData[id].epochID = uint32(epochID);
                getMemeData[id].emissionMultiple = uint32(multiple);

                emit Transfer(address(0), to, id);
            }
        }
        return id;
    }
}
