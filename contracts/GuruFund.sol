// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SignedPayload} from "contracts/helpers/EIP712Helper.sol";
import {SwapHelper} from "contracts/helpers/SwapHelper.sol";
import {TransferHelper} from "contracts/helpers/TransferHelper.sol";
import {Error} from "contracts/lib/Error.sol";
import {FundAction} from "contracts/lib/FundAction.sol";
import {InitialDeposit} from "contracts/structs/InitialDeposit.sol";
import {DepositAmounts} from "contracts/structs/DepositAmounts.sol";
import {WithdrawalAmounts} from "contracts/structs/WithdrawalAmounts.sol";
import {FundFactory} from "contracts/FundFactory.sol";
import {AssetIndex} from "contracts/structs/AssetIndex.sol";

/**
 * @title GuruFund
 * @author @numa0x
 * @notice This is the contract for a GuruFund, which is a fund handled by a manager (Guru) that invests in a set of digital assets.
 * The fund is represented by a FundToken, which is minted to the Guru when the fund is created as well as to investors when they deposit.
 * - Implements 6-decimals ERC20 for fund tokens, representing the users' shares of the fund
 * - Implements cooldowns for ERC20 transfers to have users wait before withdrawing their funds
 * - Requires signed payloads for every key operations
 * - Funds support up to 8 ERC20 assets
 * - Tracks invested capital per user to accurately compute PnL and fees
 * - Uses nonce system to prevent outdated deposit transactions
 * - Has protocol-wide pause functionality
 */
contract GuruFund is
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    SwapHelper,
    ERC20Upgradeable,
    TransferHelper
{
    using SafeERC20 for ERC20;

    /// Constants ///

    /**
     * @notice The duration of the grace period after the fund is closed. The protocol will
     * not allow any withdrawals after this period.
     */
    uint256 public constant GRACE_PERIOD_DURATION = 180 days;
    uint256 public constant MAX_DEPOSIT_COOLDOWN = 90 days;
    uint256 public constant MANAGEMENT_FEE_PERIOD = 30 days;
    /**
     * @notice The denominator for the management fee mint amount.
     * Monthly rate denominator:
     * ------------------------------------------------------------
     *   Two percent yearly rate: 2/100
     * * Pro-rated monthly: 1/12
     * = 2/100 * 1/12 = 2/1200 = 1/600
     * ------------------------------------------------------------
     * So: if the minted amount needs to be 1/600 of the total supply AFTER the mint,
     * then we need to mint 1/599 of the total supply BEFORE the mint.
     */
    uint256 public constant MANAGEMENT_FEE_DENOMINATOR = 599;

    /// States ///

    /**
     * @notice The factory that created this fund.
     */
    FundFactory public immutable fundFactory;

    /**
     * @notice Whether the fund is open for deposits and withdrawals.
     */
    bool public isOpen;

    /**
     * @notice The fund's assets
     */
    ERC20[8] public assets;

    /**
     * @notice A nonce updated on every rebalance, to prevent users from
     * submitting deposits with outdated swaps.
     */
    uint256 public nonce;

    /**
     * @notice The minimum deposit value for a user to deposit into the fund.
     */
    uint256 public minUserDepositValue;

    /**
     * @notice The minimum time for a user to wait before withdrawing their deposit
     */
    uint256 public minUserDepositCooldown;

    /**
     * @notice The timestamp of the last management fee mint
     */
    uint256 public latestManagementFeeMint;

    /**
     * @notice The end of the grace period after the Guru closed the fund, users can
     * withdraw their funds up to this timestamp
     */
    uint256 public gracePeriodEnd;

    /**
     * @notice The invested capital for each user.
     * @dev This is the sum of the positive TVL deltas during deposits, subtracted
     * of all capital removed through withdrawals.
     */
    mapping(address => uint256) public investedCapital;

    /**
     * @notice The cooldowns of the users
     */
    mapping(address => CooldownsByUser) private _cooldownsByUser;

    /**
     * @notice User deposit cooldown entry
     * @dev The offset is used to skip the cooldowns that have already been processed
     */
    struct CooldownsByUser {
        uint256 offset;
        Cooldown[] cooldowns;
    }

    /**
     * @param timestamp The timestamp of the cooldown end
     * @param amount The amount of tokens that are still locked
     */
    struct Cooldown {
        uint256 timestamp;
        uint256 amount;
    }

    /// Events ///

    /**
     * @notice Emitted when a deposit is made to the fund from a Disciple.
     * @param from The address of the Disciple
     * @param tvlDelta The TVL difference between the initial TVL and the final TVL
     * @param amountsWei The deposit amounts in wei units
     * @param amountsValue The deposit amounts in USDT units
     */
    event Deposited(
        address indexed from,
        int256 tvlDelta,
        uint256 fundTokensMinted,
        DepositAmounts amountsWei,
        DepositAmounts amountsValue
    );

    /**
     * @notice Emitted when an ERC20 asset is added into the fund by the Guru.
     * @param asset The asset deposited
     * @param amount The amount of the asset deposited
     * @param tvlDelta The TVL difference between the initial TVL and the final TVL
     */
    event DepositedAsset(ERC20 asset, uint256 amount, int256 tvlDelta);

    /**
     * @notice Emitted when the assets of the fund are updated.
     * @param assets The updated list of assets
     */
    event AssetsUpdated(ERC20[8] assets);

    /**
     * @notice Emitted when the fund is rebalanced.
     */
    event Rebalanced();

    /**
     * @notice Emitted when a user withdraws their share of the fund.
     * This will swap the assets back to ETH and return it to the user.
     * @param from The address of the user liquidating
     * @param burnAmount The amount of Fund tokens burned
     * @param amountsWei The withdrawal amounts in wei units
     * @param amountsValue The withdrawal amounts in USDT units
     * @param tvlDelta The TVL difference between the initial TVL and the final TVL
     */
    event Withdrawn(
        address indexed from,
        uint256 burnAmount,
        WithdrawalAmounts amountsWei,
        WithdrawalAmounts amountsValue,
        int256 tvlDelta
    );

    /**
     * @notice Emitted when the fund is closed by the Guru
     */
    event Closed();

    /**
     * @notice Emitted when the minimum deposit value for a user is updated.
     * @param newMinimum The new minimum deposit value
     */
    event MinUserDepositValueUpdated(uint256 newMinimum);

    /**
     * @notice Emitted when the minimum deposit cooldown for a user is updated.
     * @param newMinimum The new minimum deposit cooldown
     */
    event MinUserDepositCooldownUpdated(uint256 newMinimum);

    /**
     * @notice Emitted when the management fee is minted.
     * @param amount The amount of management fee minted
     */
    event ManagementFeeMinted(uint256 amount);

    /**
     * @notice Emitted when the grace period is extended.
     * @param newGracePeriodEnd The new grace period end
     */
    event GracePeriodExtended(uint256 newGracePeriodEnd);

    /**
     * @notice Emitted when the protocol owner claims remaining funds for buyback and burn
     */
    event AbandonedFundsClaimed();

    // errors
    error FundClosed();
    error ProtocolHalted();
    error UnexpectedFeeData(
        uint256 fees,
        uint256 maxExpectedFees,
        address feeRecipient
    );
    error MaxCooldownExceeded(uint256 cooldown);
    error DepositMustIncreaseTvl(int256 tvlDelta);
    error InvalidDepositNonce(uint256 depositNonce, uint256 currentNonce);
    error InvalidSwapDirection(address tokenFrom, address tokenTo);
    error AssetIndexAlreadyOccupied(uint8 index, ERC20 assetAtIndex);
    error CooldownNotExpired(uint256 availableBalance, uint256 transferAmount);
    error InvalidTransferAmount(
        uint256 availableBalance,
        uint256 transferAmount
    );
    error ManagementFeePeriodNotElapsed();
    error GracePeriodEnded();

    // modifiers
    modifier onlyOpen() {
        require(isOpen, FundClosed());
        _;
    }

    modifier onlyNotPaused() {
        require(!fundFactory.paused(), ProtocolHalted());
        _;
    }

    modifier verifyingSignature(SignedPayload calldata _payload) {
        fundFactory.verifySignature(msg.sender, _payload);
        _;
    }

    /**
     * @dev This will only be called once when deploying the Fund Factory.
     * Clones initializers will be called by the FundFactory.
     */
    constructor() {
        fundFactory = FundFactory(msg.sender);
        _disableInitializers();
    }

    /// External Functions ///

    /**
     * @notice Initializes the fund with a deposit of ETH, which is wrapped.
     * @dev Only the fund factory can call this function, after verifying the signature of the payload.
     * @param _guru The address of the Guru (owner) of the fund
     * @param _initialDeposit The initial deposit of the fund
     */
    function initialize(
        address _guru,
        string calldata _name,
        string calldata _symbol,
        InitialDeposit calldata _initialDeposit
    ) external payable initializer {
        require(msg.sender == address(fundFactory), Error.Unauthorized());
        require(
            _initialDeposit.minUserDepositCooldown <= MAX_DEPOSIT_COOLDOWN,
            MaxCooldownExceeded(_initialDeposit.minUserDepositCooldown)
        );

        __SwapHelper_init_unchained(
            address(fundFactory.weth()),
            address(fundFactory.vault())
        );
        __Ownable_init_unchained(_guru);
        __ERC20_init_unchained(_name, _symbol);

        // Open the fund
        minUserDepositValue = _initialDeposit.minUserDepositValue;
        minUserDepositCooldown = _initialDeposit.minUserDepositCooldown;
        latestManagementFeeMint = block.timestamp; // Allows first mint in the next period
        isOpen = true;

        // Wrap the initial deposit net amount
        _wrapETH(msg.value - _initialDeposit.amountsWei.buybackFee);

        // Initialize the assets array with WETH
        assets[0] = ERC20(address(fundFactory.weth()));

        emit AssetsUpdated(assets);

        // Mint the fund tokens to the Guru
        _mint(_guru, _initialDeposit.amountsValue.input);

        // Update the invested capital
        investedCapital[_guru] = uint256(_initialDeposit.amountsValue.input);

        // Handle buyback and burn
        _safeTransferETH(
            fundFactory.guruBurner(),
            _initialDeposit.amountsWei.buybackFee
        );

        emit Deposited(
            _guru,
            int256(_initialDeposit.amountsValue.input), // first ∆ TVL is the initial deposit value
            _initialDeposit.amountsValue.input, // first deposit mint amount matches its USDT value
            _initialDeposit.amountsWei,
            _initialDeposit.amountsValue
        );
    }

    /**
     * @notice Gurus can call this function to directly deposit an asset into the fund.
     * @param _signedAssetDeposit The signed payload containing the asset to deposit
     */
    function depositAsset(
        SignedPayload calldata _signedAssetDeposit
    ) external nonReentrant onlyOwner verifyingSignature(_signedAssetDeposit) {
        FundAction.AssetDeposit memory _deposit = abi.decode(
            _signedAssetDeposit.data,
            (FundAction.AssetDeposit)
        );

        require(
            _deposit.tvlDelta >= 0,
            DepositMustIncreaseTvl(_deposit.tvlDelta)
        );

        /// 1. Update asset index
        require(
            assets[_deposit.assetIndex] == ERC20(address(0)) ||
                assets[_deposit.assetIndex] == _deposit.asset,
            AssetIndexAlreadyOccupied(
                _deposit.assetIndex,
                assets[_deposit.assetIndex]
            )
        );

        assets[_deposit.assetIndex] = _deposit.asset;

        /// 2. Transfer deposit in
        _deposit.asset.safeTransferFrom(
            msg.sender,
            address(this),
            _deposit.amount
        );

        /// 3. Mint fund tokens
        _mint(msg.sender, _deposit.mintAmount);

        /// 4. Update invested capital
        investedCapital[msg.sender] += uint256(_deposit.tvlDelta);

        emit DepositedAsset(_deposit.asset, _deposit.amount, _deposit.tvlDelta);
    }

    /**
     * @notice Deposits ETH into the fund, which will get swapped and rebalanced
     * accordingly to the current fund composition.
     * @param _signedDepositPayload The signed payload containing the deposit data,
     * including the amount of ETH to deposit and the swaps to execute.
     */
    function deposit(
        SignedPayload calldata _signedDepositPayload
    )
        external
        payable
        nonReentrant
        onlyOpen
        onlyNotPaused
        verifyingSignature(_signedDepositPayload)
    {
        // Prevents management from accidentally depositing into any fund
        require(msg.sender != fundFactory.admin(), Error.Unauthorized());

        FundAction.Deposit memory _deposit = abi.decode(
            _signedDepositPayload.data,
            (FundAction.Deposit)
        );

        require(
            _deposit.nonce == nonce,
            InvalidDepositNonce(_deposit.nonce, nonce)
        );

        require(
            _deposit.tvlDelta >= 0,
            DepositMustIncreaseTvl(_deposit.tvlDelta)
        );

        /// 1. Validate fees and deposit amounts

        uint256 fees = _deposit.amountsWei.fee + _deposit.amountsWei.buybackFee;

        require(
            fees <= (msg.value * fundFactory.protocolDepositFee()) / 100_000 &&
                _deposit.feeRecipient != address(0),
            UnexpectedFeeData(
                fees,
                fundFactory.protocolDepositFee(),
                _deposit.feeRecipient
            )
        );

        uint256 netDeposit = msg.value - fees;

        require(
            _deposit.amountsWei.input == netDeposit,
            Error.MismatchingDepositAmount(_deposit.amountsWei, netDeposit)
        );

        /// 2. Wrap ETH
        _wrapETH(netDeposit);

        /// 3. Loop and swap
        _executeSwaps(_deposit.swaps);

        /// 4. Mint fund tokens
        _mint(msg.sender, _deposit.mintAmount);

        /// 5. Update invested capital
        investedCapital[msg.sender] += uint256(_deposit.tvlDelta);

        /// 6. Collect fees
        if (_deposit.amountsWei.fee > 0) {
            _safeTransferETH(_deposit.feeRecipient, _deposit.amountsWei.fee);
        }

        if (_deposit.amountsWei.buybackFee > 0) {
            _safeTransferETH(
                fundFactory.guruBurner(),
                _deposit.amountsWei.buybackFee
            );
        }

        emit Deposited(
            msg.sender,
            _deposit.tvlDelta,
            _deposit.mintAmount,
            _deposit.amountsWei,
            _deposit.amountsValue
        );
    }

    /**
     * @notice Swaps tokens for ETH.
     * @param _signedSwapPayload The signed payload containing the swap data
     */
    function swapTokensForETH(
        SignedPayload calldata _signedSwapPayload
    )
        external
        nonReentrant
        onlyOpen
        onlyNotPaused
        onlyOwner
        verifyingSignature(_signedSwapPayload)
    {
        FundAction.SingleSwap memory swapAction = abi.decode(
            _signedSwapPayload.data,
            (FundAction.SingleSwap)
        );

        require(
            address(swapAction.swap.tokenOut) == address(fundFactory.weth()),
            InvalidSwapDirection(
                address(swapAction.swap.tokenIn),
                address(swapAction.swap.tokenOut)
            )
        );

        _executeSingleSwap(swapAction.swap);
        _updateAssets(swapAction.assetIndexes);

        unchecked {
            nonce++;
        }
    }

    /**
     * @notice Swaps ETH for tokens.
     * @param _signedSwapPayload The signed payload containing the swap data
     */
    function swapETHForTokens(
        SignedPayload calldata _signedSwapPayload
    )
        external
        nonReentrant
        onlyOpen
        onlyNotPaused
        onlyOwner
        verifyingSignature(_signedSwapPayload)
    {
        FundAction.SingleSwap memory swapAction = abi.decode(
            _signedSwapPayload.data,
            (FundAction.SingleSwap)
        );

        require(
            address(swapAction.swap.tokenIn) == address(fundFactory.weth()),
            InvalidSwapDirection(
                address(swapAction.swap.tokenIn),
                address(swapAction.swap.tokenOut)
            )
        );

        _executeSingleSwap(swapAction.swap);
        _updateAssets(swapAction.assetIndexes);

        unchecked {
            nonce++;
        }
    }

    /**
     * @notice Rebalances the fund by changing the allocations of the assets.
     * @param _signedRebalancePayload The signed payload containing the rebalancing data,
     * including the changes to apply to the asset lists and the swaps to execute.
     */
    function rebalance(
        SignedPayload calldata _signedRebalancePayload
    )
        external
        nonReentrant
        onlyOpen
        onlyNotPaused
        onlyOwner
        verifyingSignature(_signedRebalancePayload)
    {
        FundAction.Rebalance memory _rebalance = abi.decode(
            _signedRebalancePayload.data,
            (FundAction.Rebalance)
        );

        _updateAssets(_rebalance.assetIndexes);
        _executeSwaps(_rebalance.swaps);

        unchecked {
            nonce++;
        }

        emit Rebalanced();
    }

    /**
     * @notice Withdraws the user's share of the fund, swapping the assets back to ETH.
     * @param _signedWithdrawPayload The signed payload containing the withdrawal data,
     */
    function withdraw(
        SignedPayload calldata _signedWithdrawPayload
    ) external nonReentrant verifyingSignature(_signedWithdrawPayload) {
        if (!isOpen) {
            // Investors can withdraw only until the grace period ends
            require(block.timestamp <= gracePeriodEnd, GracePeriodEnded());
        }

        FundAction.Withdraw memory _userWithdrawal = abi.decode(
            _signedWithdrawPayload.data,
            (FundAction.Withdraw)
        );

        // 1. Burn tokens
        _burn(msg.sender, _userWithdrawal.burnAmount);

        // 2. Update invested capital
        unchecked {
            investedCapital[msg.sender] -= _userWithdrawal
                .amountsValue
                .investedCapital;
        }

        // 3. Execute swaps
        _executeSwaps(_userWithdrawal.swaps);

        // 4. Handle ETH transfers and fees
        _executeWithdrawalTransfers(_userWithdrawal.amountsWei);

        emit Withdrawn(
            msg.sender,
            _userWithdrawal.burnAmount,
            _userWithdrawal.amountsWei,
            _userWithdrawal.amountsValue,
            _userWithdrawal.tvlDelta
        );
    }

    /**
     * @notice Executes the withdrawal transfers, including fees.
     * @param amountsWei The withdrawal amounts in wei units
     */
    function _executeWithdrawalTransfers(
        WithdrawalAmounts memory amountsWei
    ) internal {
        if (amountsWei.grossPnl <= 0) {
            _unwrapETH(amountsWei.netOutput);
        } else {
            unchecked {
                _unwrapETH(
                    amountsWei.netOutput +
                        amountsWei.protocolFee +
                        amountsWei.guruFee
                );
            }

            _safeTransferETH(fundFactory.vault(), amountsWei.protocolFee);
            _safeTransferETH(owner(), amountsWei.guruFee);
        }
        _safeTransferETH(msg.sender, amountsWei.netOutput);
    }

    /**
     * @notice Mints the management fee to the admin.
     * @dev Only the management admin can call this function.
     */
    function mintManagementFee() external onlyOpen onlyNotPaused {
        require(msg.sender == fundFactory.admin(), Error.Unauthorized());
        require(
            block.timestamp - latestManagementFeeMint > MANAGEMENT_FEE_PERIOD,
            ManagementFeePeriodNotElapsed()
        );

        uint256 amount = totalSupply() / MANAGEMENT_FEE_DENOMINATOR;
        _mint(fundFactory.admin(), amount);
        latestManagementFeeMint = block.timestamp;

        emit ManagementFeeMinted(amount);
    }

    /**
     * @notice Closes the fund, liquidating all assets. Users will be able to withdraw their capital.
     * @param _signedClosePayload The signed payload containing the close data
     */
    function close(
        SignedPayload calldata _signedClosePayload
    )
        external
        nonReentrant
        onlyOpen
        onlyOwner
        verifyingSignature(_signedClosePayload)
    {
        isOpen = false;
        gracePeriodEnd = block.timestamp + GRACE_PERIOD_DURATION;

        // Liquidate all assets
        FundAction.Close memory _liquidation = abi.decode(
            _signedClosePayload.data,
            (FundAction.Close)
        );

        _executeSwaps(_liquidation.swaps);

        emit Closed();
    }

    /**
     * @notice Extends the grace period.
     * @param _newGracePeriodEnd The new grace period end
     */
    function extendGracePeriod(uint256 _newGracePeriodEnd) external {
        // Only protocol owner can extend the grace period
        require(
            msg.sender == fundFactory.owner() &&
                _newGracePeriodEnd > gracePeriodEnd,
            Error.Unauthorized()
        );
        gracePeriodEnd = _newGracePeriodEnd;
        emit GracePeriodExtended(_newGracePeriodEnd);
    }

    /**
     * @notice After the grace period ends, the protocol owner can claim any
     * remaining funds to buyback and burn $GURU.
     */
    function claimAbandonedFundsForBuybackAndBurn() external {
        require(
            !isOpen &&
                msg.sender == fundFactory.owner() &&
                block.timestamp > gracePeriodEnd,
            Error.Unauthorized()
        );
        _unwrapETH(fundFactory.weth().balanceOf(address(this)));
        _safeTransferETH(fundFactory.guruBurner(), address(this).balance);
        emit AbandonedFundsClaimed();
    }

    /**
     * @notice Updates the minimum deposit value for a user.
     * @param _newMinValue The new minimum deposit value
     */
    function updateMinUserDepositValue(
        uint256 _newMinValue
    ) external onlyOpen onlyOwner {
        minUserDepositValue = _newMinValue;
        emit MinUserDepositValueUpdated(_newMinValue);
    }

    /**
     * @notice Updates the minimum deposit cooldown for a user.
     * @param _newMinCooldown The new minimum deposit cooldown
     */
    function updateMinDepositCooldown(
        uint256 _newMinCooldown
    ) external onlyOpen onlyOwner {
        require(
            _newMinCooldown <= MAX_DEPOSIT_COOLDOWN,
            MaxCooldownExceeded(_newMinCooldown)
        );
        minUserDepositCooldown = _newMinCooldown;
        emit MinUserDepositCooldownUpdated(_newMinCooldown);
    }

    /**
     * @notice Returns the available balance for a user, i.e. the balance that is not cooling down.
     * @param _account The address of the user
     * @return availableBalance The available balance for the user
     */
    function availableBalanceOf(
        address _account
    ) external view returns (uint256 availableBalance) {
        availableBalance = balanceOf(_account);

        if (hasCooldown(_account)) {
            (uint256 lockedBalance, ) = _getCooldownDetails(_account);
            availableBalance -= lockedBalance;
        }
    }

    /**
     * @notice Returns the assets of the fund.
     */
    function getAssets() external view returns (ERC20[8] memory) {
        if (isOpen) {
            return assets;
        } else {
            ERC20[8] memory _assets;
            _assets[0] = ERC20(address(fundFactory.weth()));
            return _assets;
        }
    }

    /**
     * @notice Returns the cooldown details for a user.
     * @param _account The address of the user
     * @return cooldownDetails The cooldown details for the user
     */
    function getCooldownByUser(
        address _account
    ) public view returns (CooldownsByUser memory) {
        return _cooldownsByUser[_account];
    }

    /// Public Functions ///

    /**
     * @dev [ERC20] Using 6 decimals to match USDT precision
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @notice Returns whether a user has a cooldown.
     * @param _account The address of the user
     * @return Whether the user has a cooldown
     */
    function hasCooldown(address _account) public view returns (bool) {
        return _cooldownsByUser[_account].cooldowns.length > 0;
    }

    /**
     * @notice Disable direct token transfers
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert Error.Unauthorized();
    }

    /**
     * @notice Disable direct token transfers
     */
    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        revert Error.Unauthorized();
    }

    /**
     * @notice Transfers shares to another account updating the invested capital.
     * @param to The address of the recipient
     * @param amount The amount of shares to transfer
     * @return Whether the transfer was successful
     */
    function transferShares(address to, uint256 amount) public returns (bool) {
        uint256 senderBalance = balanceOf(msg.sender);
        // Validate transfer amount
        require(
            senderBalance >= amount && amount != 0,
            InvalidTransferAmount(senderBalance, amount)
        );

        // Update invested capital for both sender and recipient when transferring between accounts
        unchecked {
            // Transfer amount validation ensures arithmetic safety: cannot divide by zero
            uint256 capitalTransferred = (amount *
                investedCapital[msg.sender]) / senderBalance;
            // `capitalTransferred` is proportional to `amount`, which is capped to sender balance,
            // so it cannot exceed sender's invested capital
            investedCapital[msg.sender] -= capitalTransferred;
            investedCapital[to] += capitalTransferred;
        }

        _transfer(msg.sender, to, amount);

        return true;
    }

    /**
     * @notice Disable ownership renouncement
     */
    function renounceOwnership() public pure override {
        revert Error.Unauthorized();
    }

    /**
     * @notice Transfer ownership to a new address
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        require(newOwner != address(0), Error.Unauthorized());

        uint256 ownerBalance = balanceOf(owner());
        if (ownerBalance > 0) {
            transferShares(newOwner, ownerBalance);
        }

        _transferOwnership(newOwner);
    }

    /// Internal Functions ///

    /**
     * @dev Wraps ETH into WETH
     */
    function _wrapETH(uint256 amount) internal {
        fundFactory.weth().deposit{value: amount}();
    }

    /**
     * @dev Unwraps WETH into ETH
     */
    function _unwrapETH(uint256 amount) internal {
        fundFactory.weth().withdraw(amount);
    }

    /**
     * @dev Updates the fund asset list.
     * NOTE: Validation of these asset list updates is done off-chain
     * @param _updates The updates to apply
     */
    function _updateAssets(AssetIndex[] memory _updates) internal {
        for (uint8 i = 0; i < _updates.length; i++) {
            assets[_updates[i].index] = _updates[i].asset;
        }

        emit AssetsUpdated(assets);
    }

    /**
     * @notice Returns the cooldown details for a user.
     * NOTE: this assumes that the user does have a cooldown, meaning:
     * `_cooldownsByUser[_user].cooldowns.length > 0`
     * @dev The offset represents the index before which all cooldowns have expired.
     * The loop is checking backwards, from the end of the cooldowns array (most
     * recent) to the beginning (earliest) and stopping when it finds a cooldown that
     * has eventually expired. This means that any previous cooldowns are also expired,
     * and we can update the offset with the current index.
     * @param account The address of the user
     * @return coolingDownBalance User balance that is still locked due to cooldown
     * @return offset The index offset of the cooldowns array, possibly to be updated in
     * the _cooldownsByUser struct: all cooldowns before this offset are expired.
     */
    function _getCooldownDetails(
        address account
    ) internal view returns (uint256 coolingDownBalance, uint256 offset) {
        uint256 newOffset = _cooldownsByUser[account].cooldowns.length;
        offset = _cooldownsByUser[account].offset;

        while (newOffset > offset) {
            Cooldown memory _cooldown = _cooldownsByUser[account].cooldowns[
                newOffset - 1
            ];
            if (block.timestamp <= _cooldown.timestamp) {
                unchecked {
                    coolingDownBalance += _cooldown.amount;
                    newOffset--;
                }
            } else {
                offset = newOffset;
            }
        }
    }

    /**
     * @dev [ERC20] Overrides the default ERC20 _update function to implement cooldown logic.
     * @param from The address of the user
     * @param to The address of the recipient
     * @param amount The amount of tokens to transfer
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (isOpen) {
            if (from == address(0) && to != fundFactory.admin()) {
                // When minting tokens (except for management fee), apply cooldown:
                _cooldownsByUser[to].cooldowns.push(
                    Cooldown({
                        timestamp: block.timestamp + minUserDepositCooldown,
                        amount: amount
                    })
                );
            } else if (hasCooldown(from)) {
                // Otherwise check cooldown for user:
                (uint256 lockedBalance, uint256 offset) = _getCooldownDetails(
                    from
                );

                // NOTE: lockedBalance is the amount of tokens that are still locked due to cooldown.
                // Therefore, the available balance for the user is:
                uint256 availableBalance = balanceOf(from) - lockedBalance;
                require(
                    availableBalance >= amount,
                    CooldownNotExpired(availableBalance, amount)
                );

                if (offset == _cooldownsByUser[from].cooldowns.length) {
                    delete _cooldownsByUser[from];
                } else {
                    _cooldownsByUser[from].offset = offset;
                }
            }
        }

        super._update(from, to, amount);
    }

    /**
     * @dev Allows contract to unwrap WETH
     */
    receive() external payable {}
}
