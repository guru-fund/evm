// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

struct DepositAmounts {
    /**
     * @notice The raw amount input to the contract by the user
     */
    uint256 input;
    /**
     * @notice Protocol fees either for project vault or referral
     */
    uint256 fee;
    /**
     * @notice Fees to be used for buybacks and burn
     */
    uint256 buybackFee;
}
