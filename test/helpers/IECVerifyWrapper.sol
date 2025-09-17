// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.5.0;

interface IECVerifyWrapper {
    function ecrecovery(bytes32 hash, bytes calldata sig) external pure returns (address);
    function ecrecovery(bytes32 hash, uint8 v, bytes32 r, bytes32 s) external pure returns (address);
    function ecverify(bytes32 hash, bytes calldata sig, address signer) external pure returns (bool);
}
