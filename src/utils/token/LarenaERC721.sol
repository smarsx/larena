// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

/// @notice ERC721 implementation optimized for larena by packing balanceOf/ownerOf with user/attribute data.
/// @author smarsx.eth
/// @author Modified from Art-Gobblers. (https://github.com/artgobblers/art-gobblers/blob/master/src/utils/token/GobblersERC721.sol)
/// @author Modified from Solmate. (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC721.sol)
abstract contract LarenaERC721 {
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
                            Larena/ERC721 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct holding larena data.
    struct LarenaData {
        // Order in respective epoch.
        uint32 index;
        // Multiple on coin issuance.
        uint32 emissionMultiple;
        // Epoch larena belongs to.
        uint32 epochID;
        // Current owner.
        address owner;
    }

    /// @notice Struct holding data relevant to each user's account.
    struct UserData {
        // The total number of larenas currently owned by the user.
        uint32 larenasOwned;
        // The sum of the multiples of all larenas the user holds.
        uint32 emissionMultiple;
        // Timestamp of the last goo balance checkpoint.
        uint64 lastTimestamp;
        // User's goo balance at time of last checkpointing.
        uint128 lastBalance;
    }

    /// @notice Maps larena ids to their data.
    mapping(uint256 => LarenaData) public getLarenaData;
    /// @notice Maps user addresses to their account data.
    mapping(address => UserData) public getUserData;

    function ownerOf(uint256 id) external view returns (address owner) {
        require((owner = getLarenaData[id].owner) != address(0), "NOT_MINTED");
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "ZERO_ADDRESS");

        return getUserData[owner].larenasOwned;
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
        address owner = getLarenaData[id].owner;

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
        // because larena.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to msg.sender who cannot be zero.

        // set emission multiple
        uint256 multiple = 9; // beyond 10000

        // The branchless expression below is equivalent to:
        //      if (id <= 3054) multiple = 5;
        // else if (id <= 5672) multiple = 6;
        // else if (id <= 7963) multiple = 7;
        // else if (id <= 10000) multiple = 8;
        assembly {
            // prettier-ignore
            multiple := sub(sub(sub(sub(
                multiple,
                lt(id, 10001)),
                lt(id, 7964)),
                lt(id, 5673)),
                lt(id, 3055)
            )
        }

        getLarenaData[id].owner = to;
        getLarenaData[id].index = uint32(index);
        getLarenaData[id].epochID = uint32(epochID);
        getLarenaData[id].emissionMultiple = uint32(multiple);

        unchecked {
            ++getUserData[to].larenasOwned;
            getUserData[to].emissionMultiple += uint32(multiple);
        }

        emit Transfer(address(0), to, id);
    }

    function _batchMint(
        address to,
        uint256 id,
        uint256 epochID,
        uint256 index,
        uint256 count
    ) internal returns (uint256) {
        // Does not check if the token was already minted or the recipient is address(0)
        // because larena.sol manages its ids in such a way that it ensures it won't
        // double mint and will only mint to owner who cannot be zero.

        // set emission multiple
        uint256 multiple = 9; // beyond 10000

        // The branchless expression below is equivalent to:
        //      if (id <= 3054) multiple = 5;
        // else if (id <= 5672) multiple = 6;
        // else if (id <= 7963) multiple = 7;
        // else if (id <= 10000) multiple = 8;
        assembly {
            // prettier-ignore
            multiple := sub(sub(sub(sub(
                multiple,
                lt(id, 10001)),
                lt(id, 7964)),
                lt(id, 5673)),
                lt(id, 3055)
            )
        }

        unchecked {
            getUserData[to].larenasOwned += uint32(count);
            getUserData[to].emissionMultiple += uint32(multiple * count);

            for (uint256 i = 0; i < count; ++i) {
                getLarenaData[++id].owner = to;
                getLarenaData[id].index = uint32(index + i);
                getLarenaData[id].epochID = uint32(epochID);
                getLarenaData[id].emissionMultiple = uint32(multiple);

                emit Transfer(address(0), to, id);
            }
        }
        return id;
    }
}
