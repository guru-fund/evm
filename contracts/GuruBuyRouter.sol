// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import { IUniswapV2Router02 } from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import { GURU } from 'contracts/$GURU.sol';
import { IWETH } from 'contracts/interfaces/IWETH.sol';

contract GuruBuyRouter {
    GURU public constant $GURU =
        GURU(payable(0xaA7D24c3E14491aBaC746a98751A4883E9b70843));

    IWETH public constant $WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IUniswapV2Router02 public constant router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public admin;

    mapping(address => bool) public allowed;

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice Sets the allowed status of an address.
     * @param _address The address to set the allowed status of.
     * @param _allowed The allowed status to set.
     */
    function setAllowed(address _address, bool _allowed) external {
        require(msg.sender == admin, 'NA');
        allowed[_address] = _allowed;
    }

    /**
     * @notice Updates the admin address.
     * @param _admin The new admin address.
     */
    function updateAdmin(address _admin) external {
        require(msg.sender == admin, 'NA');
        admin = _admin;
    }

    /**
     * @notice Swaps WETH for GURU. This contract is to be exempt from buy tax so there will be no buy tax on the swap.
     * @param amountIn The amount of WETH to swap.
     * @param amountOutMin The minimum amount of GURU to receive.
     * @param path The path of the swap.
     * @param to The address to send the GURU to.
     * @param deadline The deadline of the swap.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        require(
            allowed[msg.sender] &&
                path[0] == address($WETH) &&
                path[1] == address($GURU),
            'NA'
        );

        $WETH.transferFrom(msg.sender, address(this), amountIn);
        $WETH.approve(address(router), amountIn);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            deadline
        );

        $GURU.transfer(to, $GURU.balanceOf(address(this)));
    }
}
