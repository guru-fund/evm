// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import 'contracts/structs/Swap.sol';

contract SwapHelper is Initializable {
    using SafeERC20 for ERC20;

    address public weth;
    address public feeCollector;

    function __SwapHelper_init_unchained(
        address _weth,
        address _feeCollector
    ) internal onlyInitializing {
        weth = _weth;
        feeCollector = _feeCollector;
    }

    event SwapExecuted(
        address indexed sender,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountSent,
        uint256 amountReceived,
        address router
    );

    /**
     * @notice Execute the swaps in the provided order, based on the swap type and fee tier
     * @param _swaps The swaps to execute
     */
    function _executeSwaps(Swap[] memory _swaps) internal {
        for (uint8 i = 0; i < _swaps.length; i++) {
            _executeSingleSwap(_swaps[i]);
        }
    }

    /**
     * @notice Executes a single swap.
     * @param _swap The swap to execute
     */
    function _executeSingleSwap(Swap memory _swap) internal {
        uint256 tokenInBalanceBefore = _swap.tokenIn.balanceOf(address(this));
        uint256 tokenOutBalanceBefore = _swap.tokenOut.balanceOf(address(this));

        // Approve the router to spend the tokenIn
        _swap.tokenIn.forceApprove(address(_swap.router), _swap.amountToSend);

        // Forward the call to the router
        (bool success, bytes memory returnData) = _swap.router.call(
            _swap.callData
        );
        require(success, string(returnData));

        ERC20(weth).safeTransfer(feeCollector, _swap.swapFee);

        uint256 tokenInBalanceAfter = _swap.tokenIn.balanceOf(address(this));
        uint256 tokenOutBalanceAfter = _swap.tokenOut.balanceOf(address(this));

        emit SwapExecuted(
            msg.sender,
            address(_swap.tokenIn),
            address(_swap.tokenOut),
            tokenInBalanceBefore - tokenInBalanceAfter,
            tokenOutBalanceAfter - tokenOutBalanceBefore,
            _swap.router
        );
    }
}
