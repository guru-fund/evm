// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import 'contracts/structs/DepositAmounts.sol';

library Error {
    error InvalidAddress();
    error Unauthorized();
    error MismatchingDepositAmount(
        DepositAmounts depositAmounts,
        uint256 msgValue
    );
}
