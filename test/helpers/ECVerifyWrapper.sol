pragma solidity ^0.5.2;

import "../../contracts/ECVerify.sol";

contract ECVerifyWrapper {
    function ecrecovery(bytes32 hash, bytes memory sig) public pure returns (address) {
        return ECVerify.ecrecovery(hash, sig);
    }

    function ecrecovery(bytes32 hash, uint8 v, bytes32 r, bytes32 s) public pure returns (address) {
        return ECVerify.ecrecovery(hash, v, r, s);
    }

    function ecverify(bytes32 hash, bytes memory sig, address signer) public pure returns (bool) {
        return ECVerify.ecverify(hash, sig, signer);
    }
}
