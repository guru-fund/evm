// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

struct WithdrawalAmounts {
    /**
     * @notice The withdrawn portion of the user's capital
     * that was invested in the fund
     */
    uint256 investedCapital;
    /**
     * @notice The gross PNL: positive for profit, negative for loss
     */
    int256 grossPnl;
    /**
     * @notice Guru's fee (0 if at loss)
     */
    uint256 guruFee;
    /**
     * @notice The protocol fee (0 if at loss)
     */
    uint256 protocolFee;
    /**
     * @notice The net amount of ETH received by the user.
     * In case of a profit: user will receive more than their invested capital, deducted of fee.
     * In case of a loss: fees will be zero but the user will receive less than their invested capital.
     * @dev netOutput = investedCapital + grossPnl - guruFee - protocolFee
     */
    uint256 netOutput;
}
