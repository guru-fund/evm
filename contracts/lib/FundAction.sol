// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import { Swap } from 'contracts/structs/Swap.sol';
import { AssetIndex } from 'contracts/structs/AssetIndex.sol';
import { DepositAmounts } from 'contracts/structs/DepositAmounts.sol';
import { WithdrawalAmounts } from 'contracts/structs/WithdrawalAmounts.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

library FundAction {
    struct Deposit {
        /**
         * @notice The nonce at the time of the deposit
         */
        uint256 nonce;
        /**
         * @notice Deposit amounts in wei units
         */
        DepositAmounts amountsWei;
        /**
         * @notice Deposit amounts in USDT units
         */
        DepositAmounts amountsValue;
        /**
         * @notice Swaps to be executed to maintain the fund allocations after deposit
         */
        Swap[] swaps;
        /**
         * @notice The amount of Fund tokens to mint
         */
        uint256 mintAmount;
        /**
         * @notice Either the vault or a referral address
         */
        address feeRecipient;
        /**
         * @notice The difference in TVL between the initial TVL and the final TVL
         */
        int256 tvlDelta;
    }

    struct AssetDeposit {
        /**
         * @notice The index of the asset to deposit
         */
        uint8 assetIndex;
        /**
         * @notice The asset to deposit
         */
        ERC20 asset;
        /**
         * @notice The amount of asset to deposit
         */
        uint256 amount;
        /**
         * @notice The amount of Fund tokens to mint
         */
        uint256 mintAmount;
        /**
         * @notice The difference in TVL between the initial TVL and the final TVL
         */
        int256 tvlDelta;
    }

    struct Rebalance {
        /**
         * @notice Updates to the fund assets
         */
        AssetIndex[] assetIndexes;
        /**
         * @notice Swaps to be executed to rebalance the fund allocations
         */
        Swap[] swaps;
    }

    struct SingleSwap {
        /**
         * @notice The indexes of the assets to swap
         */
        AssetIndex[] assetIndexes;
        /**
         * @notice The swap to execute
         */
        Swap swap;
    }

    struct Withdraw {
        /**
         * @notice The amount of Fund tokens to burn
         */
        uint256 burnAmount;
        /**
         * @notice Swaps to be executed to withdraw the position
         */
        Swap[] swaps;
        /**
         * @notice The amounts in wei units
         */
        WithdrawalAmounts amountsWei;
        /**
         * @notice The amounts in USDT units
         */
        WithdrawalAmounts amountsValue;
        /**
         * @notice The difference in TVL between the initial TVL and the final TVL
         */
        int256 tvlDelta;
    }

    struct Close {
        /**
         * @notice Swaps to be executed to liquidate the fund
         */
        Swap[] swaps;
    }
}
