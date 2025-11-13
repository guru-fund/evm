// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

contract TransferHelper {
    mapping(address => uint256) creditByAddress;

    event CreditAdded(address indexed creditor, uint256 value);
    event CreditWithdrawn(address indexed recipient, uint256 value);

    error NativeTransferFailed();

    /**
     * @notice Safe transfer of ETH to an address. If the transfer fails, the value is added to the credit of the address.
     * @param recipient The address to transfer ETH to
     * @param value The amount of ETH to transfer
     */
    function _safeTransferETH(address recipient, uint256 value) internal {
        (bool success, ) = recipient.call{ value: value }('');

        if (!success) {
            creditByAddress[recipient] += value;
            emit CreditAdded(recipient, value);
        }
    }

    /**
     * @notice Withdraws the caller's credit to the specified recipient. This transfer will either succeed or revert.
     * @param recipient The address to transfer the ETH to
     */
    function withdrawCredit(address recipient) external {
        uint256 value = creditByAddress[msg.sender];
        creditByAddress[msg.sender] = 0;
        (bool success, ) = recipient.call{ value: value }('');
        require(success, NativeTransferFailed());
        emit CreditWithdrawn(recipient, value);
    }
}
