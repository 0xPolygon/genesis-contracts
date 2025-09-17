// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.5.0;

interface IValidatorVerifier {
    function isProducer(address signer) external view returns (bool);
    function isValidator(address signer) external view returns (bool);
    function isValidatorSetContract() external view returns (bool);
    function validatorSet() external view returns (address);
}
