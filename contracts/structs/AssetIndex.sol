// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
 * @notice Data structure including the index of the asset in the asset list and the new asset address
 */
struct AssetIndex {
    /**
     * @notice Index of the asset in the asset list
     */
    uint8 index;
    /**
     * @notice Address of the new asset (0x0 to remove the asset at the index)
     */
    ERC20 asset;
}
