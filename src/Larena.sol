// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*

|¯¯|  /’\  |¯¯|\¯¯\|¯¯|\¯¯\|¯¯\|¯¯|  /’\    
|^^| /_o_\ |  |/  ||   >¯_||   \  | /_o_\  
|__|/_____\|__|\__\|__|/__/|__||__|/_____\

*/

import {Owned} from "solmate/auth/Owned.sol";
import {LibGOO} from "goo-issuance/LibGOO.sol";
import {LogisticToLinearVRGDA} from "VRGDAs/LogisticToLinearVRGDA.sol";

import {SSTORE2} from "./libraries/SSTORE2.sol";
import {NFTMeta} from "./libraries/NFTMeta.sol";
import {LibString} from "./libraries/LibString.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {toDaysWadUnsafe, toWadUnsafe} from "./libraries/SignedWadMath.sol";

import {UnrevealedURI} from "./interfaces/UnrevealedURI.sol";
import {DelegatePage} from "./interfaces/DelegatePage.sol";
import {LarenaERC721} from "./utils/token/LarenaERC721.sol";
import {Pages} from "./Pages.sol";
import {Coin} from "./Coin.sol";

/// @title larena
/// On-chain user-generated autonomous art competition.
/// @author smarsx.eth
/// Inspired by Art Gobblers, Basepaint, and inscriptions.
/// @custom:experimental This is an experimental contract. (NO PROFESSIONAL AUDIT, USE AT YOUR OWN RISK)
contract Larena is LarenaERC721, LogisticToLinearVRGDA, Owned {
    using LibString for uint256;

    /// @dev The day the switch from a logistic to translated linear VRGDA is targeted to occur.
    int256 internal constant SWITCH_DAY_WAD = 1230e18;

    /// @notice The minimum amount of pages that must be sold for the VRGDA issuance
    /// schedule to switch from logistic to linear formula.
    int256 internal constant SOLD_BY_SWITCH_WAD = 9930e18;

    /// @notice Max submissions per epoch.
    uint256 public constant MAX_SUBMISSIONS = 100;

    /// @notice The royalty denominator (bps).
    uint256 internal constant ROYALTY_DENOMINATOR = 10000;

    /// @notice Length of time until admin recovery of claims is allowed.
    uint256 internal constant RECOVERY_PERIOD = 420 days;

    /// @notice Length of time epoch is active.
    uint256 public constant EPOCH_LENGTH = 30 days + 1 hours;

    /// @notice Submissions are not allowed in the 48 hours preceeding end of epoch.
    uint256 public constant SUBMISSION_DEADLINE = EPOCH_LENGTH - 48 hours;

    /// @notice Voting power decays exponentially in the 12 hours preceeding end of epoch.
    /// @dev = EPOCH_LENGTH - 12 hours
    uint256 internal constant DECAY_ZONE = 30 days - 11 hours;

    /// @notice number allowed to be minted to vault per epoch.
    /// @dev decreases each epoch until switchover
    uint256 internal constant INITIAL_VAULT_SUPPLY_PER_EPOCH = 30;
    uint256 internal constant VAULT_SUPPLY_SWITCHOVER = 28;
    uint256 internal constant VAULT_SUPPLY_PER_EPOCH = 2;

    /// @notice Payout details.
    uint256 internal constant GOLD_SHARE = 85000;
    uint256 internal constant SILVER_SHARE = 8000;
    uint256 internal constant BRONZE_SHARE = 4000;
    uint256 internal constant VAULT_SHARE = 3000;
    uint256 internal constant PAYOUT_DENOMINATOR = 100000;

    /// @notice The address of Reserve vault.
    address public immutable $vault;

    /// @notice The address of Coin contract.
    Coin public immutable $coin;

    /// @notice The address of Pages contract.
    Pages public immutable $pages;

    /// @notice The address of Unrevealed contract.
    UnrevealedURI public $unrevealed;

    /// @notice The last minted token id.
    /// @dev packed into slot 7 following $unrevealed
    uint64 public $prevTokenID;

    /// @notice Initial epoch timestamp.
    /// @dev packed into slot slot 7 following $unrevealed
    uint32 public $start;

    /// @notice The url to access larena uri.
    /// @dev BaseURI takes precedence over on-chain render in tokenURI.
    /// @dev Can always call _tokenURI to use on-chain render.
    string public $baseURI;

    /*//////////////////////////////////////////////////////////////
                            STRUCTURES / MAPPINGS
    //////////////////////////////////////////////////////////////*/

    enum ClaimType {
        GOLD,
        SILVER,
        BRONZE,
        VAULT,
        // vault_mint doesn't conceptually belong here
        // not a claim like the other fields but functions identically.
        VAULT_MINT
    }

    struct Epoch {
        uint8 claims; // each bit represents a bool for ClaimType.
        uint16 firstTokenID;
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
    event ChangedUnrevealedUri(address newPointer);
    event Claimed(uint256 indexed pageID, uint256 amt);
    event CrownedWinners(
        uint256 indexed epochID,
        uint256 goldPageID,
        uint256 silverPageID,
        uint256 bronzePageID
    );
    event CoinBalanceUpdated(address indexed user, uint256 newCoinBalance);
    event Recovered(uint256 indexed epochID);
    event Started();
    event Submitted(
        address indexed owner,
        uint256 indexed epochID,
        uint256 pageID,
        uint256 royalty,
        address pointer
    );
    event SubmittedDelegate(
        address indexed owner,
        uint256 indexed epochID,
        uint256 pageID,
        uint256 royalty,
        address pointer
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
    /// @param _coin Address of the Coin contract.
    /// @param _pages Address of the Pages contract.
    /// @param _vault Address of the reserve vault.
    constructor(
        Coin _coin,
        Pages _pages,
        UnrevealedURI _unrevealed,
        address _vault
    )
        LarenaERC721("larena", "LARENA")
        Owned(msg.sender)
        LogisticToLinearVRGDA(
            .0125e18, // Target price.
            0.31e18, // Price decay percent.
            10000e18, // Logistic asymptote.
            0.0138e18, // Logistic time scale.
            SOLD_BY_SWITCH_WAD,
            SWITCH_DAY_WAD,
            0.3e18 // linear target per day.
        )
    {
        $coin = _coin;
        $pages = _pages;
        $unrevealed = _unrevealed;
        $vault = _vault;
    }

    /*//////////////////////////////////////////////////////////////
                            USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mint larena
    /// @dev refunds any msg.value > price
    function mint() public payable {
        (uint256 epochID, ) = _currentEpoch();

        // unrealistic for price, proceeds, and tokenid to overflow
        unchecked {
            uint256 price = _getPrice($start, $prevTokenID);
            if (msg.value < price) revert InsufficientFunds();

            uint256 tokenID = ++$prevTokenID;
            $epochs[epochID].proceeds += uint136(price);

            if ($epochs[epochID].firstTokenID == 0) {
                // overflow possible in ~4500 years
                $epochs[epochID].firstTokenID = uint16(tokenID);
            }

            _mint(msg.sender, tokenID, epochID, ++tokenID - $epochs[epochID].firstTokenID);

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
        if (block.timestamp > estart + SUBMISSION_DEADLINE) revert InvalidTime();

        address pointer = SSTORE2.write(
            NFTMeta.constructTokenURI(
                NFTMeta.MetaParams({
                    typeUri: _typeUri,
                    name: string.concat("larena #", epochID.toString()),
                    description: _description,
                    duri: _duri
                })
            )
        );

        $pages.setMetadata(_pageID, _royalty, pointer, false);
        $submissions[epochID].push(_pageID);
        // pack epoch_end into votes to save an sload in vote().
        $votes[_pageID] = Vote(uint40(estart + EPOCH_LENGTH), 0);
        emit Submitted(msg.sender, epochID, _pageID, _royalty, pointer);
    }

    /// @notice Submit delegate page to an epoch.
    /// @param _pageID Page token to use.
    /// @param _royalty Royalty in basis points.
    /// @param _pointer Delegate page contract. Must implement DelegatePage interface.
    function submitDelegate(uint256 _pageID, uint256 _royalty, address _pointer) external {
        (uint256 epochID, uint256 estart) = _currentEpoch();

        if ($pages.ownerOf(_pageID) != msg.sender) revert NotOwner();
        if ($submissions[epochID].length >= MAX_SUBMISSIONS) revert MaxSupply();
        if (block.timestamp > estart + SUBMISSION_DEADLINE) revert InvalidTime();

        $pages.setMetadata(_pageID, _royalty, _pointer, true);
        $submissions[epochID].push(_pageID);
        $votes[_pageID] = Vote(uint40(estart + EPOCH_LENGTH), 0);
        emit SubmittedDelegate(msg.sender, epochID, _pageID, _royalty, _pointer);
    }

    /// @notice Vote for a page.
    /// @param _pageID Page to cast vote for.
    /// @param _coin Amount of coin to spend.
    /// @param _useVirtualBalance Use virtual balance vs erc20 wallet balance.
    /// @dev vote utilization is decreased exponentially in the 12 hours preceeding end of epoch.
    function vote(uint256 _pageID, uint256 _coin, bool _useVirtualBalance) external {
        uint256 pvotes = $votes[_pageID].votes;
        uint256 epochEnd = $votes[_pageID].epochEnd;
        if (block.timestamp >= epochEnd) revert InvalidTime();

        // update user coin balance
        // reverts on balance < _coin
        _useVirtualBalance
            ? updateUserCoinBalance(msg.sender, _coin, CoinBalanceUpdateType.DECREASE)
            : $coin.burnCoin(msg.sender, _coin);

        assembly {
            // timestamp > deadzone_start
            if gt(timestamp(), add(sub(epochEnd, EPOCH_LENGTH), DECAY_ZONE)) {
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
                _coin := div(mul(_coin, utilization), 1000)
            }
            // add coin to votes
            // overflow to uint216 is unlikely on human timelines
            pvotes := add(pvotes, _coin)
        }

        $votes[_pageID].votes = uint216(pvotes);
        emit Voted(_pageID, _coin, msg.sender);
    }

    /// @notice Claim winnings.
    /// @param _epochID epoch being claimed.
    /// @param _claimType type of claim (gold, silver, bronze).
    /// @dev caller must be owner of page being claimed.
    function claim(uint256 _epochID, ClaimType _claimType) external {
        Epoch memory e = $epochs[_epochID];
        uint256 pageId = getClaimPageId(_claimType, e.goldPageID, e.silverPageID, e.bronzePageID);

        if ($pages.ownerOf(pageId) != msg.sender) revert NotOwner();
        if (e.claims & (1 << uint8(_claimType)) != 0) revert DuplicateClaim();

        // claim
        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(_claimType)));

        uint256 claimAmount = unsafeDivMul(
            e.proceeds,
            getClaimShare(_claimType),
            PAYOUT_DENOMINATOR
        );

        emit Claimed(pageId, claimAmount);
        SafeTransferLib.safeTransferETH(msg.sender, claimAmount);
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

    /// @notice Mint to vault.
    function vaultMint() external {
        (uint256 epochID, ) = _currentEpoch();
        Epoch memory e = $epochs[epochID];

        if (e.claims & (1 << uint8(ClaimType.VAULT_MINT)) != 0) revert DuplicateClaim();

        // claim
        $epochs[epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.VAULT_MINT)));

        uint256 prevID = $prevTokenID;
        uint256 nextID = prevID + 1;
        uint256 vaultNum = getVaultSupply(epochID);
        unchecked {
            if (e.firstTokenID == 0) {
                $epochs[epochID].firstTokenID = uint16(nextID);
            }
            // use ++nextID for 1-based index.
            uint256 firstIndex = ++nextID - $epochs[epochID].firstTokenID;
            $prevTokenID = uint56(_batchMint($vault, prevID, epochID, firstIndex, vaultNum));
        }
    }

    /// @notice Claim vault share.
    function vaultClaim(uint256 _epochID) external {
        Epoch memory e = $epochs[_epochID];

        if (_epochID == 0) revert InvalidTime();
        if (e.claims & (1 << uint8(ClaimType.VAULT)) != 0) revert DuplicateClaim();

        // claim
        $epochs[_epochID].claims = uint8(e.claims | (1 << uint8(ClaimType.VAULT)));

        // vault_share = proceeds - sum(gold, silver, bronze)
        // cleans up rounding crumbs

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

    /// @notice Calculate a user's virtual coin balance.
    /// @param _user The user to query balance for.
    function coinBalance(address _user) public view returns (uint256) {
        // Compute the user's virtual coin balance using LibGOO
        // prettier-ignore
        return LibGOO.computeGOOBalance(
            getUserData[_user].emissionMultiple,
            getUserData[_user].lastBalance,
            uint256(toDaysWadUnsafe(block.timestamp - getUserData[_user].lastTimestamp))
        );
    }

    /// @notice Add coin to your emission balance,
    /// burning the corresponding ERC20 balance.
    /// @param _coinAmount The amount of coin to add.
    function addCoin(uint256 _coinAmount) external {
        // Burn coin being added to larena
        $coin.burnCoin(msg.sender, _coinAmount);

        // Increase msg.sender's virtual coin balance
        updateUserCoinBalance(msg.sender, _coinAmount, CoinBalanceUpdateType.INCREASE);
    }

    /// @notice Remove coin from your emission balance, and
    /// add the corresponding amount to your ERC20 balance.
    /// @param _coinAmount The amount of coin to remove.
    function removeCoin(uint256 _coinAmount) external {
        // Decrease msg.sender's virtual coin balance
        updateUserCoinBalance(msg.sender, _coinAmount, CoinBalanceUpdateType.DECREASE);

        // Mint the corresponding amount of ERC20 coin
        $coin.mintCoin(msg.sender, _coinAmount);
    }

    /// @notice Burn an amount of a user's virtual coin balance. Only callable
    /// by the Pages contract to enable purchasing pages with virtual balance.
    /// @param _user The user whose virtual coin balance we should burn from.
    /// @param _coinAmount The amount of coin to burn from the user's virtual balance.
    function burnCoinForPages(address _user, uint256 _coinAmount) external {
        // The caller must be the Pages contract, revert otherwise
        if (msg.sender != address($pages)) revert InsufficientFunds();

        // Burn the requested amount of coin from the user's virtual coin balance
        // Will revert if the user doesn't have enough coin in their virtual balance
        updateUserCoinBalance(_user, _coinAmount, CoinBalanceUpdateType.DECREASE);
    }

    /// @dev An enum for representing whether to
    /// increase or decrease a user's coin balance.
    enum CoinBalanceUpdateType {
        INCREASE,
        DECREASE
    }

    /// @notice Update a user's virtual coin balance.
    /// @param _user The user whose virtual coin balance we should update.
    /// @param _coinAmount The amount of coin to update the user's virtual balance by.
    /// @param _updateType Whether to increase or decrease the user's balance by coinAmount.
    function updateUserCoinBalance(
        address _user,
        uint256 _coinAmount,
        CoinBalanceUpdateType _updateType
    ) internal {
        // Will revert due to underflow if we're decreasing by more than the user's current balance
        // Don't need to do checked addition in the increase case, but we do it anyway for convenience
        uint256 updatedBalance = _updateType == CoinBalanceUpdateType.INCREASE
            ? coinBalance(_user) + _coinAmount
            : coinBalance(_user) - _coinAmount;

        // Snapshot the user's new coin balance with the current timestamp
        getUserData[_user].lastBalance = uint128(updatedBalance);
        getUserData[_user].lastTimestamp = uint64(block.timestamp);

        emit CoinBalanceUpdated(_user, updatedBalance);
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
        LarenaData memory ld = getLarenaData[_id];
        Epoch memory epoch = $epochs[ld.epochID];
        if (ld.epochID == 0) revert InvalidID();

        if (epoch.goldPageID == 0) {
            // unrevealed
            return $unrevealed.tokenUri(ld.epochID, ld.index);
        } else {
            // revealed
            Pages.Metadata memory meta = $pages.GetMetadata(_id);
            return
                meta.delegate
                    ? DelegatePage(meta.pointer).tokenURI(ld.epochID, ld.emissionMultiple, ld.index)
                    : NFTMeta.renderWithTraits(ld.emissionMultiple, SSTORE2.read(meta.pointer));
        }
    }

    /// @notice Transfer
    function transferFrom(address from, address to, uint256 id) public override {
        require(from == getLarenaData[id].owner, "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from ||
                isApprovedForAll[from][msg.sender] ||
                msg.sender == getApproved[id],
            "NOT_AUTHORIZED"
        );

        delete getApproved[id];

        getLarenaData[id].owner = to;

        unchecked {
            uint32 emissionMultiple = getLarenaData[id].emissionMultiple; // Caching saves gas

            // We update their last balance before updating their emission multiple to avoid
            // penalizing them by retroactively applying their new (lower) emission multiple
            getUserData[from].lastBalance = uint128(coinBalance(from));
            getUserData[from].lastTimestamp = uint64(block.timestamp);
            getUserData[from].emissionMultiple -= emissionMultiple;
            getUserData[from].larenasOwned -= 1;

            // We update their last balance before updating their emission multiple to avoid
            // overpaying them by retroactively applying their new (higher) emission multiple
            getUserData[to].lastBalance = uint128(coinBalance(to));
            getUserData[to].lastTimestamp = uint64(block.timestamp);
            getUserData[to].emissionMultiple += emissionMultiple;
            getUserData[to].larenasOwned += 1;
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
        LarenaData memory ld = getLarenaData[_tokenId];

        address owner = $pages.ownerOf($epochs[ld.epochID].goldPageID);
        Pages.Metadata memory meta = $pages.GetMetadata(_tokenId);

        return (owner, (_salePrice * uint256(meta.royalty)) / ROYALTY_DENOMINATOR);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(LarenaERC721) returns (bool) {
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

    /// @notice Update base URI string.
    function updateUnrevealedURI(address _pointer) external onlyOwner {
        $unrevealed = UnrevealedURI(_pointer);
        emit ChangedUnrevealedUri(_pointer);
    }

    /// @notice Sweep unclaimed funds to vault.
    /// @dev timestamp must be > RECOVERY_PERIOD.
    function recoverPayout(uint256 _epochID) external onlyOwner {
        uint256 startTime = _epochStart(_epochID);
        if (startTime + RECOVERY_PERIOD > block.timestamp) revert();

        Epoch memory e = $epochs[_epochID];

        // already recovered
        if (uint256(e.claims) == 255) revert();

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

    /// @notice Get page ids submitted to an epoch.
    function getSubmissions(uint256 _epochID) public view returns (uint256[] memory) {
        return $submissions[_epochID];
    }

    /// @notice Get active epochID and its respective start time.
    function currentEpoch() public view returns (uint256, uint256) {
        return _currentEpoch();
    }

    /// @notice Get starting timestamp of given epoch
    /// @dev if id = 0 this will overflow
    function epochStart(uint256 _id) public view returns (uint256) {
        return _epochStart(_id);
    }

    /// @notice Get active VRGDA price.
    /// @return Current price in wei.
    function getPrice() public view returns (uint256) {
        if ($start == 0) revert InvalidTime();
        return _getPrice($start, $prevTokenID);
    }

    /// @notice Get active epochID and its respective start time.
    function _currentEpoch() internal view returns (uint256 _epochID, uint256 _start) {
        assembly {
            // load slot7, extract $start
            _start := and(shr(224, sload(7)), 0xffffffff)
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
            _start := add(mul(sub(_id, 1), EPOCH_LENGTH), and(shr(224, sload(7)), 0xffffffff))
        }
    }

    /// @notice Get VRGDA price given parameters.
    /// @return Current price in wei.
    function _getPrice(uint256 _mintStart, uint256 _numMinted) internal view returns (uint256) {
        unchecked {
            uint256 timeSinceStart = block.timestamp - _mintStart;
            return getVRGDAPrice(toDaysWadUnsafe(timeSinceStart), _numMinted);
        }
    }

    /// @notice unsafebutsafedivmul
    /// @dev _x is constrained by price of ether, _y & _d are defined constants
    function unsafeDivMul(
        uint256 _x,
        uint256 _y,
        uint256 _d
    ) internal pure returns (uint256 _result) {
        assembly {
            _result := div(mul(_x, _y), _d)
        }
    }

    /// @notice Get vault supply for given epoch.
    function getVaultSupply(uint256 _epochID) internal pure returns (uint256) {
        unchecked {
            return
                _epochID > VAULT_SUPPLY_SWITCHOVER
                    ? VAULT_SUPPLY_PER_EPOCH
                    : INITIAL_VAULT_SUPPLY_PER_EPOCH - _epochID;
        }
    }

    // helpers for readability
    function getClaimShare(ClaimType _ct) internal pure returns (uint256) {
        if (_ct == ClaimType.GOLD) {
            return GOLD_SHARE;
        } else if (_ct == ClaimType.SILVER) {
            return SILVER_SHARE;
        } else if (_ct == ClaimType.BRONZE) {
            return BRONZE_SHARE;
        }
        revert("Invalid Claim Type");
    }

    function getClaimPageId(
        ClaimType _ct,
        uint256 goldID,
        uint256 silverID,
        uint256 bronzeID
    ) internal pure returns (uint256) {
        if (_ct == ClaimType.GOLD) {
            return goldID;
        } else if (_ct == ClaimType.SILVER) {
            return silverID;
        } else if (_ct == ClaimType.BRONZE) {
            return bronzeID;
        }
        revert("Invalid Claim Type");
    }
}
