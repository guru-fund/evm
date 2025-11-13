// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

struct SignedPayload {
    /**
     * @notice Encoded payload
     */
    bytes data;
    /**
     * @notice Signature of the payload
     */
    bytes signature;
    /**
     * @notice Expiration block number of the payload
     */
    uint256 expiresAt;
}
