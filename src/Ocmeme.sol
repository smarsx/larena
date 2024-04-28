// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
     ░░░░░░   ░░░░░░ ░░░    ░░░ ░░░░░░░ ░░░    ░░░ ░░░░░░░
    ▒▒    ▒▒ ▒▒      ▒▒▒▒  ▒▒▒▒ ▒▒      ▒▒▒▒  ▒▒▒▒ ▒▒     
    ▒▒    ▒▒ ▒▒      ▒▒ ▒▒▒▒ ▒▒ ▒▒▒▒▒   ▒▒ ▒▒▒▒ ▒▒ ▒▒▒▒▒  
    ▓▓    ▓▓ ▓▓      ▓▓  ▓▓  ▓▓ ▓▓      ▓▓  ▓▓  ▓▓ ▓▓     
     ██████   ██████ ██      ██ ███████ ██      ██ ███████
*/

import {Owned} from "solmate/auth/Owned.sol";
import {LibGOO} from "goo-issuance/LibGOO.sol";
import {LogisticToLinearVRGDA} from "VRGDAs/LogisticToLinearVRGDA.sol";

import {SSTORE2} from "./libraries/SSTORE2.sol";
import {NFTMeta} from "./libraries/NFTMeta.sol";
import {LibString} from "./libraries/LibString.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {toDaysWadUnsafe, toWadUnsafe} from "./libraries/SignedWadMath.sol";

import {OcmemeERC721} from "./utils/token/OcmemeERC721.sol";
import {Pages} from "./Pages.sol";
import {Goo} from "./Goo.sol";

/// @title OCmeme
/// On-chain user-generated autonomous art competition.
/// @author smarsx.eth
/// Inspired by Art Gobblers (https://github.com/artgobblers/art-gobblers).
/// @custom:experimental This is an experimental contract. (NO PROFESSIONAL AUDIT, USE AT YOUR OWN RISK)
contract Ocmeme is OcmemeERC721, LogisticToLinearVRGDA, Owned {
    using LibString for uint256;

    /// @dev The day the switch from a logistic to translated linear VRGDA is targeted to occur.
    int256 internal constant SWITCH_DAY_WAD = 1800e18;

    /// @notice The minimum amount of pages that must be sold for the VRGDA issuance
    /// schedule to switch from logistic to linear formula.
    int256 internal constant SOLD_BY_SWITCH_WAD = 9994.930541e18;

    /// @notice Initial number allowed to be minted to vault per epoch.
    /// @dev decreases over time eventually to zero.
    /// @dev at switch to linear, vault supply will be ~5% of total supply.
    uint256 public constant INITIAL_VAULT_SUPPLY_PER_EPOCH = 30;

    /// @notice Max submissions per epoch.
    uint256 public constant MAX_SUBMISSIONS = 100;

    /// @notice The royalty denominator (bps).
    uint256 public constant ROYALTY_DENOMINATOR = 10000;

    /// @notice Length of time until admin recovery of claims is allowed.
    uint256 public constant RECOVERY_PERIOD = 420 days;

    /// @notice Length of time epoch is active.
    uint256 public constant EPOCH_LENGTH = 30 days + 1 hours;

    /// @notice Submissions are not allowed in the 48 hours preceeding end of epoch.
    uint256 public constant SDEADZONE = 30 days - 47 hours;

    /// @notice Votes are ~exponentially nerfed (but still allowed) in hours preceeding end of epoch.
    uint256 public constant VDEADZONE = 30 days - 11 hours;

    /// @notice Payout details.
    uint256 public constant GOLD_SHARE = 85;
    uint256 public constant SILVER_SHARE = 8;
    uint256 public constant BRONZE_SHARE = 4;
    uint256 public constant VAULT_SHARE = 3;
    uint256 public constant PAYOUT_DENOMINATOR = 100;

    /// @notice The address of Reserve vault.
    address public immutable $vault;

    /// @notice The address of Goo contract.
    Goo public immutable $goo;

    /// @notice The address of Pages contract.
    Pages public immutable $pages;

    /// @notice The last minted token id.
    uint64 public $prevTokenID;

    /// @notice Initial epoch timestamp.
    uint32 public $start;

    /// @notice The url to access ocmeme uri.
    /// @dev BaseURI takes precedence over on-chain render in tokenURI.
    /// @dev Can always call _tokenURI to use on-chain render.
    string public $baseURI;

    /*//////////////////////////////////////////////////////////////
                                STRUCTURES
    //////////////////////////////////////////////////////////////*/

    enum ClaimType {
        GOLD,
        SILVER,
        BRONZE,
        VAULT,
        // vault_mint doesn't conceptually belong here
        // not a claim like the other fields.
        VAULT_MINT
    }

    struct Epoch {
        // each bit represents a bool for ClaimType.
        uint8 claims;
        // num tokens minted for epoch.
        uint16 count;
        // winning pages
        uint32 goldPageID;
        uint32 silverPageID;
        uint32 bronzePageID;
        // total proceeds.
        uint136 proceeds;
    }

    struct Vote {
        uint40 epochEnd;
        uint216 votes;
    }

    mapping(uint256 pageID => Vote) public $votes;
    mapping(uint256 epochID => Epoch) public $epochs;
    mapping(uint256 epochID => uint256[]) public $submissions;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event ChangedBaseURI(string baseURI);
    event Claimed(uint256 indexed pageID, uint256 amt);
    event CrownedWinners(
        uint256 indexed epochID,
        uint256 goldPageID,
        uint256 silverPageID,
        uint256 bronzePageID
    );
    event Deadzoned(uint256 indexed epochID);
    event GooBalanceUpdated(address indexed user, uint256 newGooBalance);
    event Recovered(uint256 indexed epochID);
    event Started();
    event Submitted(
        address indexed owner,
        uint256 indexed epochID,
        uint256 pageID,
        uint256 royalty
    );
    event Voted(uint256 indexed pageID, uint256 amt, address from);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DuplicateClaim();
    error InsufficientFunds();
    error InvalidID();
    error InvalidTime();
    error MaxSupply();
    error NotOwner();
    error WinnerSet();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets up initial conditions.
    /// @param _goo Address of the Goo contract.
    /// @param _pages Address of the Pages contract.
    /// @param _vault Address of the reserve vault.
    constructor(
        Goo _goo,
        Pages _pages,
        address _vault
    )
        OcmemeERC721("OCMEME", "OCMEME")
        Owned(msg.sender)
        LogisticToLinearVRGDA(
            .025e18, // Target price.
            0.31e18, // Price decay percent.
            10000e18, // Logistic asymptote.
            0.0138e18, // Logistic time scale.
            SOLD_BY_SWITCH_WAD,
            SWITCH_DAY_WAD,
            0.03e18 // linear target per day.
        )
    {
        $goo = _goo;
        $pages = _pages;
        $vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                            USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint ocmeme
    function mint() public payable {
        (uint256 epochID, ) = _currentEpoch();

        // unrealistic for price, or proceeds to overflow
        unchecked {
            uint256 price = _getPrice($start, $prevTokenID);
            if (msg.value < price) revert InsufficientFunds();

            ++$epochs[epochID].count;
            $epochs[epochID].proceeds += uint136(price);

            _mint(msg.sender, ++$prevTokenID, epochID, $epochs[epochID].count);

            // refund overpaid
            SafeTransferLib.safeTransferETH(msg.sender, msg.value - price);
        }
    }

    /// @notice Submit page to an epoch.
    /// @param _pageID Page token to use.
    /// @param _royalty Royalty in basis points.
    /// @param _typeUri Data key in tokenuri output.
    /// @param _description Description in tokenuri output.
    /// @param _duri DataURI value.
    function submit(
        uint256 _pageID,
        uint256 _royalty,
        NFTMeta.TypeURI _typeUri,
        string calldata _description,
        string calldata _duri
    ) external {
        (uint256 epochID, uint256 estart) = _currentEpoch();

        if ($pages.ownerOf(_pageID) != msg.sender) revert NotOwner();
        if ($submissions[epochID].length >= MAX_SUBMISSIONS) revert MaxSupply();
        if (block.timestamp > estart + SDEADZONE) revert InvalidTime();

        address pointer = SSTORE2.write(
            NFTMeta.constructTokenURI(
                NFTMeta.MetaParams({
                    typeUri: _typeUri,
                    name: string.concat("OCmeme #", epochID.toString()),
                    description: _description,
                    duri: _duri
                })
            )
        );

        $pages.setMetadata(_pageID, _royalty, pointer);
        $submissions[epochID].push(_pageID);
        $votes[_pageID] = Vote(uint40(estart + EPOCH_LENGTH), 0);
        emit Submitted(msg.sender, epochID, _pageID, _royalty);
    }

    /// @notice Vote for a page.
    /// @param _pageID Page to cast vote for.
    /// @param _goo Amount of goo to spend.
    /// @param _useVirtualBalance Use virtual balance vs erc20 wallet balance.
    /// @dev vote utilization is decreased exponentially in the 12 hours preceeding end of epoch.
    function vote(uint256 _pageID, uint256 _goo, bool _useVirtualBalance) external {
        uint256 pvotes = $votes[_pageID].votes;
        uint256 epochEnd = $votes[_pageID].epochEnd;
        if (block.timestamp >= epochEnd) revert InvalidTime();

        // update user goo balance
        // reverts on balance < _goo
        _useVirtualBalance
            ? updateUserGooBalance(msg.sender, _goo, GooBalanceUpdateType.DECREASE)
            : $goo.burnGoo(msg.sender, _goo);

        assembly {
            // timestamp > deadzone_start
            if gt(timestamp(), add(sub(epochEnd, EPOCH_LENGTH), VDEADZONE)) {
                let hrsRem := div(sub(epochEnd, timestamp()), 3600)
                let utilization := 100
                // roughly follow e^-.4x
                // prettier-ignore
                switch hrsRem
                    case 12 { utilization := 973 }
                    case 11 { utilization := 963 }
                    case 10 { utilization := 950 }
                    case 9 { utilization := 933 }
                    case 8 { utilization := 909 }
                    case 7 { utilization := 878 }
                    case 6 { utilization := 835 }
                    case 5 { utilization := 777 }
                    case 4 { utilization := 699 }
                    case 3 { utilization := 593 }
                    case 2 { utilization := 451 }
                    case 1 { utilization := 259 }
                // muldiv to reach utilization
                _goo := div(mul(_goo, utilization), 1000)
            }
            // add goo to votes
            // overflow to uint216 is unlikely on human timelines
            pvotes := add(pvotes, _goo)
        }

        $votes[_pageID].votes = uint216(pvotes);
        emit Voted(_pageID, _goo, msg.sender);
    }

    /// @notice Claim gold winnings.
    /// @dev must be owner of goldPageID.
    function claimGold(uint256 _epochID) external {
        Epoch memory e = $epochs[_epochID];
        if ($pages.ownerOf(e.goldPageID) != msg.sender) revert NotOwner();
        if (e.claims & (1 << uint8(ClaimType.GOLD)) != 0) revert DuplicateClaim();

        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.GOLD)));

        uint256 amt;
        uint256 p = uint256(e.proceeds);
        assembly {
            amt := div(mul(p, GOLD_SHARE), PAYOUT_DENOMINATOR)
        }

        emit Claimed(e.goldPageID, amt);
        SafeTransferLib.safeTransferETH(msg.sender, amt);
    }

    /// @notice Claim silver winnings.
    /// @dev must be owner of silverPageID.
    function claimSilver(uint256 _epochID) external {
        Epoch memory e = $epochs[_epochID];
        if ($pages.ownerOf(e.silverPageID) != msg.sender) revert NotOwner();
        if (e.claims & (1 << uint8(ClaimType.SILVER)) != 0) revert DuplicateClaim();

        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.SILVER)));

        uint256 amt;
        uint256 p = uint256(e.proceeds);
        assembly {
            amt := div(mul(p, SILVER_SHARE), PAYOUT_DENOMINATOR)
        }

        emit Claimed(e.silverPageID, amt);
        SafeTransferLib.safeTransferETH(msg.sender, amt);
    }

    /// @notice Claim bronze winnings.
    /// @dev must be owner of bronzePageID.
    function claimBronze(uint256 _epochID) external {
        Epoch memory e = $epochs[_epochID];
        if ($pages.ownerOf(e.bronzePageID) != msg.sender) revert NotOwner();
        if (e.claims & (1 << uint8(ClaimType.BRONZE)) != 0) revert DuplicateClaim();

        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.BRONZE)));

        uint256 amt;
        uint256 p = uint256(e.proceeds);
        assembly {
            amt := div(mul(p, BRONZE_SHARE), PAYOUT_DENOMINATOR)
        }

        emit Claimed(e.bronzePageID, amt);
        SafeTransferLib.safeTransferETH(msg.sender, amt);
    }

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Crown winners for previous epoch.
    /// @dev pages[0] can undeservingly win silver/bronze if < 3 pages w/ votes > 0
    /// this is non-issue w/ minimal participation.
    function crownWinners() external {
        (uint256 epochID, ) = _currentEpoch();
        // use previous epoch.
        // _currentEpoch will revert before this can overflow.
        unchecked {
            epochID -= 1;
        }

        if ($epochs[epochID].goldPageID > 0) revert WinnerSet();

        uint256 gold;
        uint256 goldIdx;
        uint256 silver;
        uint256 silverIdx;
        uint256 bronze;
        uint256 bronzeIdx;
        uint256[] memory subs = $submissions[epochID];
        uint256 sublen = subs.length;

        uint256 lvotes;
        for (uint256 i; i < sublen; i++) {
            lvotes = $votes[subs[i]].votes;
            if (lvotes > gold) {
                // silver -> bronze
                bronze = silver;
                bronzeIdx = silverIdx;
                // gold -> silver
                silver = gold;
                silverIdx = goldIdx;
                // new gold
                gold = lvotes;
                goldIdx = i;
            } else if (lvotes > silver) {
                // silver -> bronze
                bronze = silver;
                bronzeIdx = silverIdx;

                // new silver
                silver = lvotes;
                silverIdx = i;
            } else if (lvotes > bronze) {
                // new bronze
                bronze = lvotes;
                bronzeIdx = i;
            }
        }

        uint256 bronzePageID = subs[bronzeIdx];
        uint256 silverPageID = subs[silverIdx];
        uint256 goldPageID = subs[goldIdx];

        $epochs[epochID].bronzePageID = uint32(bronzePageID);
        $epochs[epochID].silverPageID = uint32(silverPageID);
        $epochs[epochID].goldPageID = uint32(goldPageID);

        emit CrownedWinners(epochID, goldPageID, silverPageID, bronzePageID);
    }

    /// @notice Mint vaultNum to protocol vault.
    function vaultMint() external {
        (uint256 epochID, ) = _currentEpoch();
        Epoch memory e = $epochs[epochID];
        if (e.claims & (1 << uint8(ClaimType.VAULT_MINT)) != 0) revert DuplicateClaim();

        uint256 vaultNum = epochID > 55 ? 0 : epochID > 28
            ? 2
            : INITIAL_VAULT_SUPPLY_PER_EPOCH - epochID;
        if (vaultNum == 0) revert();

        $epochs[epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.VAULT_MINT)));
        $epochs[epochID].count += uint16(vaultNum);
        $prevTokenID = uint56(
            _batchMint(address($vault), $prevTokenID, epochID, ++e.count, vaultNum)
        );
    }

    /// @notice Claim vault share.
    function claimVault(uint256 _epochID) external {
        if (_epochID == 0) revert();
        Epoch memory e = $epochs[_epochID];
        if (e.claims & (1 << uint8(ClaimType.VAULT)) != 0) revert DuplicateClaim();

        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.VAULT)));

        // vault_share = proceeds - sum(gold, silver, bronze)
        // this cleans up rounding crumbs

        uint256 amt;
        uint256 p = uint256(e.proceeds);
        assembly {
            // prettier-ignore
            amt := 
                sub(p, 
                    add(add(
                        div(mul(p, GOLD_SHARE), PAYOUT_DENOMINATOR),
                        div(mul(p, SILVER_SHARE), PAYOUT_DENOMINATOR)),
                        div(mul(p, BRONZE_SHARE), PAYOUT_DENOMINATOR)
                    )
                )
        }

        emit Claimed(0, amt);
        SafeTransferLib.safeTransferETH($vault, amt);
    }

    /*//////////////////////////////////////////////////////////////
                                GOO LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate a user's virtual goo balance.
    /// @param _user The user to query balance for.
    function gooBalance(address _user) public view returns (uint256) {
        // Compute the user's virtual goo balance using LibGOO
        // prettier-ignore
        return LibGOO.computeGOOBalance(
            getUserData[_user].emissionMultiple,
            getUserData[_user].lastBalance,
            uint256(toDaysWadUnsafe(block.timestamp - getUserData[_user].lastTimestamp))
        );
    }

    /// @notice Add goo to your emission balance,
    /// burning the corresponding ERC20 balance.
    /// @param _gooAmount The amount of goo to add.
    function addGoo(uint256 _gooAmount) external {
        // Burn goo being added to ocmeme
        $goo.burnGoo(msg.sender, _gooAmount);

        // Increase msg.sender's virtual goo balance
        updateUserGooBalance(msg.sender, _gooAmount, GooBalanceUpdateType.INCREASE);
    }

    /// @notice Remove goo from your emission balance, and
    /// add the corresponding amount to your ERC20 balance.
    /// @param _gooAmount The amount of goo to remove.
    function removeGoo(uint256 _gooAmount) external {
        // Decrease msg.sender's virtual goo balance
        updateUserGooBalance(msg.sender, _gooAmount, GooBalanceUpdateType.DECREASE);

        // Mint the corresponding amount of ERC20 goo
        $goo.mintGoo(msg.sender, _gooAmount);
    }

    /// @notice Burn an amount of a user's virtual goo balance. Only callable
    /// by the Pages contract to enable purchasing pages with virtual balance.
    /// @param _user The user whose virtual goo balance we should burn from.
    /// @param _gooAmount The amount of goo to burn from the user's virtual balance.
    function burnGooForPages(address _user, uint256 _gooAmount) external {
        // The caller must be the Pages contract, revert otherwise
        if (msg.sender != address($pages)) revert InsufficientFunds();

        // Burn the requested amount of goo from the user's virtual goo balance
        // Will revert if the user doesn't have enough goo in their virtual balance
        updateUserGooBalance(_user, _gooAmount, GooBalanceUpdateType.DECREASE);
    }

    /// @dev An enum for representing whether to
    /// increase or decrease a user's goo balance.
    enum GooBalanceUpdateType {
        INCREASE,
        DECREASE
    }

    /// @notice Update a user's virtual goo balance.
    /// @param _user The user whose virtual goo balance we should update.
    /// @param _gooAmount The amount of goo to update the user's virtual balance by.
    /// @param _updateType Whether to increase or decrease the user's balance by gooAmount.
    function updateUserGooBalance(
        address _user,
        uint256 _gooAmount,
        GooBalanceUpdateType _updateType
    ) internal {
        // Will revert due to underflow if we're decreasing by more than the user's current balance
        // Don't need to do checked addition in the increase case, but we do it anyway for convenience
        uint256 updatedBalance = _updateType == GooBalanceUpdateType.INCREASE
            ? gooBalance(_user) + _gooAmount
            : gooBalance(_user) - _gooAmount;

        // Snapshot the user's new goo balance with the current timestamp
        getUserData[_user].lastBalance = uint128(updatedBalance);
        getUserData[_user].lastTimestamp = uint64(block.timestamp);

        emit GooBalanceUpdated(_user, updatedBalance);
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets tokenURI from baseURI or _tokenURI.
    function tokenURI(uint256 _id) public view virtual override returns (string memory) {
        return
            bytes($baseURI).length == 0
                ? _tokenURI(_id)
                : string(abi.encodePacked($baseURI, _id.toString()));
    }

    /// @notice Render tokenURI.
    function _tokenURI(uint256 _id) public view returns (string memory) {
        MemeData memory md = getMemeData[_id];
        Epoch memory e = $epochs[md.epochID];
        if (md.epochID == 0) revert InvalidID();

        if (e.goldPageID == 0) {
            // unrevealed
            return
                NFTMeta.constructBaseTokenURI(
                    md.index,
                    string.concat("OCmeme #", uint256(md.epochID).toString())
                );
        } else {
            // revealed
            Pages.Metadata memory m = $pages.GetMetadata(e.goldPageID);
            return NFTMeta.renderWithTraits(md.emissionMultiple, SSTORE2.read(m.pointer));
        }
    }

    function transferFrom(address from, address to, uint256 id) public override {
        require(from == getMemeData[id].owner, "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from ||
                isApprovedForAll[from][msg.sender] ||
                msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        delete getApproved[id];

        getMemeData[id].owner = to;

        unchecked {
            uint32 emissionMultiple = getMemeData[id].emissionMultiple; // Caching saves gas

            // We update their last balance before updating their emission multiple to avoid
            // penalizing them by retroactively applying their new (lower) emission multiple
            getUserData[from].lastBalance = uint128(gooBalance(from));
            getUserData[from].lastTimestamp = uint64(block.timestamp);
            getUserData[from].emissionMultiple -= emissionMultiple;
            getUserData[from].memesOwned -= 1;

            // We update their last balance before updating their emission multiple to avoid
            // overpaying them by retroactively applying their new (higher) emission multiple
            getUserData[to].lastBalance = uint128(gooBalance(to));
            getUserData[to].lastTimestamp = uint64(block.timestamp);
            getUserData[to].emissionMultiple += emissionMultiple;
            getUserData[to].memesOwned += 1;
        }

        emit Transfer(from, to, id);
    }

    /*///////////////////////////////////////////////////////////////////
                                EIP-2981 
    //////////////////////////////////////////////////////////////////*/

    /// @notice Called with the sale price to determine how much royalty
    // is owed and to whom.
    /// @param _tokenId The NFT asset queried for royalty information.
    /// @param _salePrice The sale price of the NFT asset specified by _tokenId.
    /// @return receiver Address of who should be sent the royalty payment.
    /// @return royaltyAmount The royalty payment amount for _salePrice.
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) external view returns (address, uint256) {
        MemeData memory md = getMemeData[_tokenId];
        uint256 winningPageId = uint256($epochs[md.epochID].goldPageID);

        address owner = $pages.ownerOf(winningPageId);
        Pages.Metadata memory m = $pages.GetMetadata(_tokenId);

        return (owner, (_salePrice * uint256(m.royalty)) / ROYALTY_DENOMINATOR);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(OcmemeERC721) returns (bool) {
        return interfaceId == 0x2a55205a || super.supportsInterface(interfaceId);
    }

    /*///////////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////////*/

    /// @notice Start Epoch 1.
    /// @dev one-time use.
    function setStart() external onlyOwner {
        if ($start != 0) revert();
        $start = uint32(block.timestamp);
        emit Started();
    }

    /// @notice Update base URI string.
    function updateBaseURI(string calldata _baseURI) external onlyOwner {
        $baseURI = _baseURI;
        emit ChangedBaseURI(_baseURI);
    }

    /// @notice Sweep unclaimed funds to vault.
    /// @dev timestamp must be > RECOVERY_PERIOD.
    function recoverPayout(uint256 _epochID) external onlyOwner {
        uint256 startTime = _epochStart(_epochID);
        if (startTime + RECOVERY_PERIOD > block.timestamp) revert InvalidTime();

        Epoch memory e = $epochs[_epochID];

        // already recovered
        if (uint256(e.claims) == 255) revert DuplicateClaim();

        // fill the bits
        $epochs[_epochID].claims = 255;

        // sum remaining claims
        uint256 amt;
        uint256 c = uint256(e.claims);
        uint256 p = uint256(e.proceeds);
        assembly {
            if iszero(and(c, shl(and(0, 0xff), 1))) {
                amt := add(amt, div(mul(p, GOLD_SHARE), PAYOUT_DENOMINATOR))
            }
            if iszero(and(c, shl(and(1, 0xff), 1))) {
                amt := add(amt, div(mul(p, SILVER_SHARE), PAYOUT_DENOMINATOR))
            }
            if iszero(and(c, shl(and(2, 0xff), 1))) {
                amt := add(amt, div(mul(p, BRONZE_SHARE), PAYOUT_DENOMINATOR))
            }
            if iszero(and(c, shl(and(3, 0xff), 1))) {
                // prettier-ignore
                amt := 
                    add(amt, 
                        sub(p, 
                            add(add(
                                div(mul(p, GOLD_SHARE), PAYOUT_DENOMINATOR),
                                div(mul(p, SILVER_SHARE), PAYOUT_DENOMINATOR)),
                                div(mul(p, BRONZE_SHARE), PAYOUT_DENOMINATOR)
                            )
                        )
                    )
            }
        }

        emit Recovered(_epochID);
        SafeTransferLib.safeTransferETH($vault, amt);
    }

    /*///////////////////////////////////////////////////////////////////
                                    UTILS
    //////////////////////////////////////////////////////////////////*/

    /// @notice Get active epochID and its respective start time.
    function currentEpoch() public view returns (uint256, uint256) {
        return _currentEpoch();
    }

    /// @notice Get starting timestamp of given epoch
    /// @dev if id = 0 this will overflow
    function epochStart(uint256 _id) public view returns (uint256) {
        return _epochStart(_id);
    }

    /// @notice Get active epochID and its respective start time.
    function _currentEpoch() internal view returns (uint256 _epochID, uint256 _start) {
        assembly {
            // load slot6, extract $start
            _start := and(shr(224, sload(6)), 0xffffffff)
            if iszero(_start) {
                mstore(0x00, 0x6f7eac26) // InvalidTime
                revert(0x1c, 0x04)
            }
            _epochID := add(div(sub(timestamp(), _start), EPOCH_LENGTH), 1)
            _start := add(mul(sub(_epochID, 1), EPOCH_LENGTH), _start)
        }
    }

    /// @notice Get starting timestamp of given epoch
    /// @dev if id = 0 this will overflow
    function _epochStart(uint256 _id) internal view returns (uint256 _start) {
        assembly {
            _start := add(mul(sub(_id, 1), EPOCH_LENGTH), and(shr(224, sload(6)), 0xffffffff))
        }
    }

    /// @notice Get active VRGDA price.
    /// @return Current price in wei.
    function getPrice() public view returns (uint256) {
        if ($start == 0) revert InvalidTime();
        return _getPrice($start, $prevTokenID);
    }

    /// @notice Get VRGDA price given parameters.
    /// @return Current price in wei.
    function _getPrice(uint256 _mintStart, uint256 _numMinted) internal view returns (uint256) {
        unchecked {
            uint256 timeSinceStart = block.timestamp - _mintStart;
            return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), _numMinted);
        }
    }

    // convenience
    function getSubmissions(uint256 _epochID) public view returns (uint256[] memory) {
        return $submissions[_epochID];
    }
}
