// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import { IWETH } from 'contracts/interfaces/IWETH.sol';

contract GuruDepositRouter {
    IWETH public constant $WETH =
        IWETH(0x4200000000000000000000000000000000000006);

    function forwardSwapETH(
        address fund,
        address router,
        uint256 amountIn,
        bytes calldata data
    ) external {
        require(fund == msg.sender, 'NA');

        $WETH.transferFrom(msg.sender, address(this), amountIn);
        $WETH.approve(address(router), amountIn);

        (bool success, ) = router.call(data);
        require(success, 'Failed to forward swap');
    }
}
