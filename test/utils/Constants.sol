contract Constants {
    /// @dev The day the switch from a logistic to translated linear VRGDA is targeted to occur.
    int256 public constant SWITCH_DAY_WAD = 1230e18;

    /// @notice The minimum amount of pages that must be sold for the VRGDA issuance
    /// schedule to switch from logistic to linear formula.
    int256 public constant SOLD_BY_SWITCH_WAD = 9930e18;

    /// @notice Max submissions per epoch.
    uint256 public constant MAX_SUBMISSIONS = 100;

    /// @notice The royalty denominator (bps).
    uint256 public constant ROYALTY_DENOMINATOR = 10000;

    /// @notice Length of time until admin recovery of claims is allowed.
    uint256 public constant RECOVERY_PERIOD = 420 days;

    /// @notice Length of time epoch is active.
    uint256 public constant EPOCH_LENGTH = 30 days + 1 hours;

    /// @notice Submissions are not allowed in the 48 hours preceeding end of epoch.
    uint256 public constant SUBMISSION_DEADLINE = EPOCH_LENGTH - 48 hours;

    /// @notice Voting power decays exponentially in the 12 hours preceeding end of epoch.
    /// @dev = EPOCH_LENGTH - 12 hours
    uint256 public constant DECAY_ZONE = 30 days - 11 hours;

    /// @notice number allowed to be minted to vault per epoch.
    /// @dev decreases each epoch until switchover
    uint256 public constant INITIAL_VAULT_SUPPLY_PER_EPOCH = 30;
    uint256 public constant VAULT_SUPPLY_SWITCHOVER = 28;
    uint256 public constant VAULT_SUPPLY_PER_EPOCH = 2;

    /// @notice Payout details.
    uint256 public constant GOLD_SHARE = 85000;
    uint256 public constant SILVER_SHARE = 8000;
    uint256 public constant BRONZE_SHARE = 4000;
    uint256 public constant VAULT_SHARE = 3000;
    uint256 public constant PAYOUT_DENOMINATOR = 100000;
}
