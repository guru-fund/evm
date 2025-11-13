// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/EIP712.sol';
import '@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol';

import 'contracts/lib/Error.sol';
import 'contracts/structs/SignedPayload.sol';

/// @title EIP712Helper: Verifies EIP712 signatures
abstract contract EIP712Helper is EIP712, Ownable {
    address private signer;
    mapping(address => uint256) public noncesByUser;

    error InvalidSignature();
    error ExpiredSignature();
    event SignerUpdated(address signer);

    /**
     * @param _name Name of the signing domain.
     * @param _version Version of the signing domain.
     * @param _signer Signer
     */
    constructor(
        string memory _name,
        string memory _version,
        address _signer
    ) EIP712(_name, _version) {
        _setOffchainSigner(_signer);
    }

    /**
     * @notice Get the off-chain signer
     * @return Signer address
     */
    function getOffchainSigner() external view returns (address) {
        return signer;
    }

    /**
     * @notice Set the off-chain signer (only Owner)
     * @param _signer New signer
     */
    function setOffchainSigner(address _signer) external onlyOwner {
        _setOffchainSigner(_signer);
    }

    /// @param _signer Signer
    function _setOffchainSigner(address _signer) internal {
        require(
            _signer != address(0) && signer != _signer,
            Error.InvalidAddress()
        );
        signer = _signer;
        emit SignerUpdated(_signer);
    }

    /**
     * @dev Verifies the signature
     * @param _typeHash Type hash
     * @param _account Address of the user the signature was signed for
     * @param _payload Signed payload containing the data, signature and expiration
     */
    function _verifyEIP712(
        bytes32 _typeHash,
        address _account,
        SignedPayload calldata _payload
    ) internal {
        require(_payload.expiresAt >= block.number, ExpiredSignature());

        unchecked {
            require(
                SignatureChecker.isValidSignatureNow(
                    signer,
                    _hashTypedDataV4(
                        keccak256(
                            abi.encode(
                                _typeHash,
                                noncesByUser[_account]++,
                                _account,
                                keccak256(_payload.data),
                                _payload.expiresAt
                            )
                        )
                    ),
                    _payload.signature
                ),
                InvalidSignature()
            );
        }
    }
}
