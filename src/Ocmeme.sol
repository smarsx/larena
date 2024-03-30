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
import {LogisticVRGDA} from "VRGDAs/LogisticVRGDA.sol";
import {toDaysWadUnsafe, toWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {SSTORE2} from "./libraries/SSTORE2.sol";
import {NFTMeta} from "./libraries/NFTMeta.sol";
import {LibString} from "./libraries/LibString.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";

import {OcmemeERC721} from "./utils/token/OcmemeERC721.sol";
import {Pages} from "./Pages.sol";
import {Goo} from "./Goo.sol";

/// @title OCmeme
/// On-chain user-generated autonomous art competition.
/// @author smarsx.eth
/// Inspired by Art Gobblers (https://github.com/artgobblers/art-gobblers).
/// @custom:experimental This is an experimental contract. (NO PROFESSIONAL AUDIT, USE AT YOUR OWN RISK)
contract Ocmeme is OcmemeERC721, LogisticVRGDA, Owned {
    using LibString for uint256;

    /// @notice Max supply per epoch.
    uint256 public constant SUPPLY_PER_EPOCH = 500;

    /// @notice Max submissions per epoch.
    uint256 public constant MAX_SUBMISSIONS = 100;

    /// @notice The royalty denominator.
    /// @dev Allows measurement in bps (basis points).
    uint256 public constant ROYALTY_DENOMINATOR = 10000;

    /// @notice Length of time until admin recovery of claims is allowed.
    uint256 public constant RECOVERY_PERIOD = 420 days;

    /// @notice Length of time epoch is active.
    uint256 public constant EPOCH_LENGTH = 30 days;

    /// @notice Length of time dead zone is active.
    /// @dev deadzone: period preceding end of epoch where
    /// submissions are not allowed and vote utilization is decreased.
    uint256 public constant DEAD_ZONE = 36 hours;

    /// @notice Length of time between start of epoch and start of dead zone.
    uint256 public constant ACTIVE_PERIOD = EPOCH_LENGTH - DEAD_ZONE;

    /// @notice Payout details.
    uint256 public constant PAYOUT_DENOMINATOR = 100;
    uint256 public constant GOLD_SHARE = 85;
    uint256 public constant SILVER_SHARE = 8;
    uint256 public constant BRONZE_SHARE = 4;
    uint256 public constant VAULT_SHARE = 3;

    /// @notice The address of Goo contract.
    Goo immutable $goo;

    /// @notice The address of Reserve vault.
    address immutable $vault;

    /// @notice The address of Pages contract.
    Pages immutable $pages;

    /// @notice The last minted token id.
    uint56 $prevTokenID;

    /// @notice Initial epoch timestamp.
    uint32 $start;

    /// @notice Allow recovery of assets.
    /// @dev initialized to 1, if flipped, cannot be changed.
    uint8 $allowRecovery;

    /// @notice The url to access ocmeme uri.
    /// @dev BaseURI takes precedence over on-chain render in tokenURI.
    /// @dev Can always call _tokenURI to use on-chain render.
    string $baseURI;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    enum ClaimType {
        GOLD,
        SILVER,
        BRONZE,
        VAULT,
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

    struct VotePair {
        uint48 dztime;
        uint208 votes;
    }

    mapping(uint256 epochID => Epoch) $epochs;
    mapping(uint256 epochID => uint256[]) $submissions;
    mapping(uint256 pageID => VotePair) $votes;

    /*//////////////////////////////////////////////////////////////
                        PUBLIC GETTERS (hold the $)
    //////////////////////////////////////////////////////////////*/

    function goo() public view returns (Goo _goo) {
        _goo = $goo;
    }

    function pages() public view returns (Pages _pages) {
        _pages = $pages;
    }

    function vault() public view returns (address _vault) {
        _vault = $vault;
    }

    function start() public view returns (uint256 _start) {
        _start = uint256($start);
    }

    function prevTokenID() public view returns (uint256 _prevTokenID) {
        _prevTokenID = uint256($prevTokenID);
    }

    function epochs(uint256 _id) public view returns (Epoch memory _epochs) {
        _epochs = $epochs[_id];
    }

    function submissions(uint256 _id) public view returns (uint256[] memory _submissions) {
        _submissions = $submissions[_id];
    }

    function votes(uint256 _pageID) public view returns (VotePair memory _votes) {
        _votes = $votes[_pageID];
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Submission(
        uint256 indexed epochID,
        address indexed creator,
        uint256 pageID,
        uint256 royalty
    );
    event Vote(uint256 indexed pageID, uint256 amt);
    event Winners(
        uint256 indexed epochID,
        uint256 goldPageID,
        uint256 silverPageID,
        uint256 bronzePageID
    );
    event Claim(uint256 indexed epochID, uint256 indexed pageID, ClaimType claimType, uint256 amt);

    event GooBalanceUpdated(address indexed user, uint256 newGooBalance);
    event SetVoteDeadzone(uint256 indexed epochID, uint256 dz);
    event SetBaseURI(string baseURI);
    event SetStart(uint256 _start);
    event Recovery(uint256 amt);
    event LockedRecovery();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidID();
    error NotOwner();
    error MaxSupply();
    error WinnerSet();
    error InvalidTime();
    error RecoveryLocked();
    error DuplicateClaim();
    error InsufficientFunds();

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
        LogisticVRGDA(
            .005e18, // Target price.
            0.31e18, // Price decay percent.
            toWadUnsafe(SUPPLY_PER_EPOCH),
            .4e18 // Per time unit.
        )
    {
        $goo = _goo;
        $pages = _pages;
        $vault = _vault;
        $allowRecovery = 1;
    }

    /*//////////////////////////////////////////////////////////////
                            USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint ocmeme
    function mint() public payable {
        (uint256 epochID, uint256 estart) = currentEpoch();
        uint256 count = $epochs[epochID].count;

        // Note: We don't need to check count < SUPPLY_PER_EPOCH, VRGDA will
        // revert if we're over the logistic asymptote.

        // unrealistic for price, or proceeds to overflow
        unchecked {
            uint256 price = _getPrice(estart, count);
            if (msg.value < price) revert InsufficientFunds();

            ++$epochs[epochID].count;
            $epochs[epochID].proceeds += uint136(price);

            _mint(msg.sender, ++$prevTokenID, epochID, ++count);

            // refund overpaid
            SafeTransferLib.safeTransferETH(msg.sender, msg.value - price);
        }
    }

    /// @notice Submit page to an epoch.
    /// @param _pageID Page token to use.
    /// @param _royalty Royalty in basis points (BPS).
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
        (uint256 epochID, uint256 estart) = currentEpoch();

        if ($pages.ownerOf(_pageID) != msg.sender) revert NotOwner();
        if ($submissions[epochID].length >= MAX_SUBMISSIONS) revert MaxSupply();
        if (block.timestamp - estart > ACTIVE_PERIOD) revert InvalidTime();

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
        emit Submission(epochID, msg.sender, _pageID, _royalty);
    }

    /// @notice Vote for a page.
    /// @param _pageID Page id to cast vote for.
    /// @param _goo Amount of goo to spend.
    /// @param _useVirtualBalance Use virtual balance vs erc20 wallet balance.
    /// @dev if deadzone is active, vote utilization is decreased 5-80%. see DEADZONE
    function vote(uint256 _pageID, uint256 _goo, bool _useVirtualBalance) external {
        // update user goo balance
        // reverts on balance < _goo
        _useVirtualBalance
            ? updateUserGooBalance(msg.sender, _goo, GooBalanceUpdateType.DECREASE)
            : $goo.burnGoo(msg.sender, _goo);

        VotePair memory vp = $votes[_pageID];
        uint256 dz = uint256(vp.dztime);
        uint256 v = uint256(vp.votes);
        assembly {
            // is deadzone period
            if and(gt(dz, 0), gt(timestamp(), dz)) {
                // calculate penalty
                let hrs := div(sub(timestamp(), dz), 3600)
                let utilization := 20
                // prettier-ignore
                switch div(hrs, 6)
                    case 0 { utilization := 95 }
                    case 1 { utilization := 90 }
                    case 2 { utilization := 80 }
                    case 3 { utilization := 65 }
                    case 4 { utilization := 45 }

                // apply deadzone penalty
                // muldiv: floor(goo * utilization / 100)
                _goo := div(mul(_goo, utilization), 100)
            }
            v := add(v, _goo)
        }

        $votes[_pageID].votes = uint208(v);
        emit Vote(_pageID, _goo);
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

        emit Claim(_epochID, e.goldPageID, ClaimType.GOLD, amt);
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

        emit Claim(_epochID, e.silverPageID, ClaimType.SILVER, amt);
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

        emit Claim(_epochID, e.bronzePageID, ClaimType.BRONZE, amt);
        SafeTransferLib.safeTransferETH(msg.sender, amt);
    }

    /*//////////////////////////////////////////////////////////////
                            PROTOCOL ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Crown winners for previous epoch.
    /// @dev pages[0] can undeservingly win silver/bronze if not enough pages w/ votes > 0
    /// this is non-issue w/ minimal participation.
    function crownWinners() external {
        (uint256 epochID, ) = currentEpoch();
        // use previous epoch.
        unchecked {
            epochID -= 1;
        }

        if ($epochs[epochID].goldPageID != 0) revert WinnerSet();

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

        emit Winners(epochID, goldPageID, silverPageID, bronzePageID);
    }

    /// @notice Pack deadzone timestamp into current epochs votepairs
    /// @dev used to pack timestamp into same slot that is loaded in Vote()
    /// @dev can be called anytime, best after deadzone start so no new submissions.
    /// @dev if never set, dz is simply ignored in Vote()
    function setVoteDeadzone() public {
        (uint256 epochID, uint256 estart) = currentEpoch();
        uint48 dztime = uint48(estart + ACTIVE_PERIOD);

        uint256[] memory lpages = $submissions[epochID];
        uint256 len = lpages.length;

        for (uint256 i; i < len; i++) {
            $votes[lpages[i]].dztime = dztime;
        }
        emit SetVoteDeadzone(epochID, dztime);
    }

    /// @notice Mint VAULT_NUM to protocol vault.
    function vaultMint() external {
        (uint256 epochID, ) = currentEpoch();
        Epoch memory e = $epochs[epochID];
        if (uint256(e.count) + VAULT_NUM > SUPPLY_PER_EPOCH) revert MaxSupply();
        if (e.claims & (1 << uint8(ClaimType.VAULT_MINT)) != 0) revert DuplicateClaim();

        $epochs[epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.VAULT_MINT)));
        $epochs[epochID].count += uint16(VAULT_NUM);
        $prevTokenID = uint56(_batchMint(address($vault), $prevTokenID, epochID, ++e.count));
    }

    /// @notice Claim vault share.
    function claimVault(uint256 _epochID) external {
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

        emit Claim(_epochID, 0, ClaimType.VAULT, amt);
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
        emit SetStart(block.timestamp);
    }

    /// @notice Turn off recovery ability.
    /// @dev one-time use.
    function deleteRecovery() external onlyOwner {
        delete $allowRecovery;
        emit LockedRecovery();
    }

    /// @notice Update base URI string.
    function updateBaseURI(string calldata _baseURI) external onlyOwner {
        $baseURI = _baseURI;
        emit SetBaseURI(_baseURI);
    }

    /// @notice If past RECOVERY_PERIOD, recover unclaimed funds to vault.
    function recoverPayout(uint256 _epochID) external onlyOwner {
        uint256 startTime = epochStart(_epochID);
        if (startTime + RECOVERY_PERIOD > block.timestamp) revert InvalidTime();
        if ($allowRecovery == 0) revert RecoveryLocked();

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

        emit Recovery(amt);
        SafeTransferLib.safeTransferETH($vault, amt);
    }

    /*///////////////////////////////////////////////////////////////////
                                    UTILS
    //////////////////////////////////////////////////////////////////*/

    /// @notice Get active epochID and its start time.
    function currentEpoch() public view returns (uint256 _epochID, uint256 _epochStart) {
        assembly {
            _epochStart := and(shr(216, sload(6)), 0xffffffff)
            if iszero(_epochStart) {
                mstore(0x00, 0x6f7eac26) // InvalidTime
                revert(0x1c, 0x04)
            }
            _epochID := add(div(sub(timestamp(), _epochStart), EPOCH_LENGTH), 1)
            _epochStart := add(mul(sub(_epochID, 1), EPOCH_LENGTH), _epochStart)
        }
    }

    /// @notice Get start time of given epoch
    /// @dev if _id = 0 this will overflow
    function epochStart(uint256 _id) public view returns (uint256 _start) {
        assembly {
            _start := add(mul(sub(_id, 1), EPOCH_LENGTH), and(shr(216, sload(6)), 0xffffffff))
        }
    }

    /// @notice Get active price.
    function getPrice() public view returns (uint256) {
        (uint256 epochID, uint256 estart) = currentEpoch();
        return _getPrice(estart, $epochs[epochID].count);
    }

    /// @notice Get VRGDA price given parameters
    /// @return Current price in wei.
    function _getPrice(uint256 _mintStart, uint256 _numMinted) internal view returns (uint256) {
        uint256 timeSinceStart = block.timestamp - _mintStart;
        unchecked {
            return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), _numMinted);
        }
    }
}
