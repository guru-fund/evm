// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import 'contracts/structs/DepositAmounts.sol';
struct InitialDeposit {
    /**
     * @notice Wei amounts of the deposit
     */
    DepositAmounts amountsWei;
    /**
     * @notice Values in USDT units
     */
    DepositAmounts amountsValue;
    /**
     * @notice Value of the min deposit in USDT units by the users
     */
    uint256 minUserDepositValue;
    /**
     * @notice Minimum time for a user to wait before withdrawing their deposit
     */
    uint256 minUserDepositCooldown;
}
