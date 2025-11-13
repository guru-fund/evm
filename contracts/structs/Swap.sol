// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

struct Swap {
    /**
     * @notice The address of the router to use for the swap
     */
    address router;
    /**
     * @notice The encoded function call data for the swap
     */
    bytes callData;
    /**
     * @notice The token to send
     */
    ERC20 tokenIn;
    /**
     * @notice The token to receive
     */
    ERC20 tokenOut;
    /**
     * @notice The amount of tokenIn, decoded for token approval
     */
    uint256 amountToSend;
    /**
     * @notice The swap fee amount we apply to this swap
     */
    uint256 swapFee;
}
