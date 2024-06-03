// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";
import {LinearVRGDA} from "VRGDAs/LinearVRGDA.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";

import {Coin} from "./Coin.sol";
import {Larena} from "./Larena.sol";
import {NFTMeta} from "./libraries/NFTMeta.sol";
import {PagesERC721} from "./utils/token/PagesERC721.sol";
import {DelegatePage} from "./interfaces/DelegatePage.sol";

/// @title Pages NFT
/// @author modified from Art-Gobblers (https://github.com/artgobblers/art-gobblers/blob/master/src/Pages.sol)
/// @notice Pages is an ERC721 with extra metadata. (royalty, votes, pointer (data))
contract Pages is PagesERC721, LinearVRGDA {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the coin ERC20 token contract.
    Coin public immutable coin;

    /// @notice The address which receives pages reserved for the community.
    address public immutable vault;

    /*//////////////////////////////////////////////////////////////
                            VRGDA INPUT STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp for the start of the VRGDA mint.
    uint256 public immutable mintStart;

    /// @notice Id of the most recently minted page.
    /// @dev Will be 0 if no pages have been minted yet.
    uint128 public currentId;

    /*//////////////////////////////////////////////////////////////
                          COMMUNITY PAGES STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The number of pages minted to the vault.
    uint128 public numMintedForVault;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PagePurchased(address indexed user, uint256 indexed pageId, uint256 price);

    event VaultPageMinted(address indexed user, uint256 lastMintedPageId, uint256 numPages);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error ReserveImbalance();

    error PriceExceededMax(uint256 currentPrice);

    error Unauthorized();

    error Used();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets VRGDA parameters, mint start, relevant addresses, and base URI.
    /// @param _mintStart Timestamp for the start of the VRGDA mint.
    /// @param _coin Address of the Coin contract.
    /// @param _vault Address of the vault.
    /// @param _larena Address of the larena contract.
    constructor(
        uint256 _mintStart,
        Coin _coin,
        address _vault,
        Larena _larena
    )
        PagesERC721(_larena, "Pages", "PAGE")
        LinearVRGDA(
            0.0042069e18, // Target price.
            0.31e18, // Price decay percent.
            4e18 // Pages to target per day.
        )
    {
        mintStart = _mintStart;
        coin = _coin;
        vault = _vault;
    }

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /*//////////////////////////////////////////////////////////////
                               METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Page metadata.
    struct Metadata {
        bool delegate;
        uint88 royalty;
        address pointer;
    }

    /// @notice Map pageIds to metadata
    mapping(uint256 => Metadata) public pageMetadata;

    /// @notice Get page metadata
    function GetMetadata(uint256 _pageID) public view returns (Metadata memory _metadata) {
        _metadata = pageMetadata[_pageID];
    }

    /// @notice Set royalty and SSTORE2 pointer for page.
    /// @dev Reverts if pointer is already set.
    /// @dev Called in larena.Submit()
    /// @dev Doesn't overwrite votes, technically you can pre-vote for x pageId.
    function setMetadata(
        uint256 _pageID,
        uint256 _royalty,
        address _pointer,
        bool _delegate
    ) external only(address(larena)) {
        if (pageMetadata[_pageID].pointer != address(0)) revert Used();
        pageMetadata[_pageID] = Metadata({
            pointer: _pointer,
            royalty: uint88(_royalty),
            delegate: _delegate
        });
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a page with coin, burning the cost.
    /// @param maxPrice Maximum price to pay to mint the page.
    /// @param useVirtualBalance Whether the cost is paid from the
    /// user's virtual coin balance, or from their ERC20 coin balance.
    /// @return pageId The id of the page that was minted.
    function mintFromCoin(
        uint256 maxPrice,
        bool useVirtualBalance
    ) external returns (uint256 pageId) {
        // Will revert if prior to mint start.
        uint256 currentPrice = pagePrice();

        // If the current price is above the user's specified max, revert.
        if (currentPrice > maxPrice) revert PriceExceededMax(currentPrice);

        // Decrement the user's coin balance by the current
        // price, either from virtual balance or ERC20 balance.
        useVirtualBalance
            ? larena.burnCoinForPages(msg.sender, currentPrice)
            : coin.burnForPages(msg.sender, currentPrice);

        unchecked {
            emit PagePurchased(msg.sender, pageId = ++currentId, currentPrice);

            _mint(msg.sender, pageId);
        }
    }

    /// @notice Calculate the mint cost of a page.
    /// @dev Reverts due to underflow if minting hasn't started yet. Done to save gas.
    function pagePrice() public view returns (uint256) {
        // We need checked math here to cause overflow
        // before minting has begun, preventing mints.
        uint256 timeSinceStart = block.timestamp - mintStart;

        unchecked {
            // The number of pages minted for the community reserve
            // should never exceed 10% of the total supply of pages.
            return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), currentId - numMintedForVault);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      COMMUNITY PAGES MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint a number of pages to the community reserve.
    /// @param numPages The number of pages to mint to the reserve.
    /// @dev Pages minted to the reserve cannot comprise more than 10% of the sum of the
    /// supply of coin minted pages and the supply of pages minted to the community reserve.
    function mintVaultPages(uint256 numPages) external returns (uint256 lastMintedPageId) {
        unchecked {
            // Optimistically increment numMintedForCommunity, may be reverted below.
            // Overflow in this calculation is possible but numPages would have to be so
            // large that it would cause the loop in _batchMint to run out of gas quickly.
            uint256 newNumMintedForCommunity = numMintedForVault += uint128(numPages);

            // Ensure that after this mint pages minted to the community reserve won't comprise more than
            // 10% of the new total page supply. currentId is equivalent to the current total supply of pages.
            if (newNumMintedForCommunity > ((lastMintedPageId = currentId) + numPages) / 10)
                revert ReserveImbalance();

            // Mint the pages to the community reserve and update lastMintedPageId once minting is complete.
            lastMintedPageId = _batchMint(vault, numPages, lastMintedPageId);

            currentId = uint128(lastMintedPageId); // Update currentId with the last minted page id.

            emit VaultPageMinted(msg.sender, lastMintedPageId, numPages);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             TOKEN URI LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a page's URI.
    /// @param pageID The id of the page to get the URI for.
    /// @dev a delegate will return only the image/animation_url data-uri
    /// @dev default page will return data:application/json;base64 with fields name,description,image or animation_url
    function tokenURI(uint256 pageID) public view virtual override returns (string memory) {
        if (pageID == 0 || pageID > currentId) revert("NOT_MINTED");
        if (pageMetadata[pageID].pointer == address(0)) revert("NOT_SET");
        return
            pageMetadata[pageID].delegate
                ? DelegatePage(pageMetadata[pageID].pointer).tokenURI()
                : NFTMeta.render(SSTORE2.read(pageMetadata[pageID].pointer));
    }
}
