// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.5.0;

struct Validator {
    uint256 id;
    uint256 power;
    address signer;
}

struct Span {
    uint256 number;
    uint256 startBlock;
    uint256 endBlock;
}

event NewSpan(uint256 indexed id, uint256 indexed startBlock, uint256 indexed endBlock);

interface IBorValidatorSet {
    function BOR_ID() external view returns (bytes32);
    function CHAIN() external view returns (bytes32);
    function FIRST_END_BLOCK() external view returns (uint256);
    function ROUND_TYPE() external view returns (bytes32);
    function SPRINT() external view returns (uint256);
    function SYSTEM_ADDRESS() external view returns (address);
    function VOTE_TYPE() external view returns (uint8);
    function checkMembership(bytes32 rootHash, bytes32 leaf, bytes memory proof) external pure returns (bool);
    function commitSpan(uint256 newSpan, uint256 startBlock, uint256 endBlock, bytes memory validatorBytes, bytes memory producerBytes) external;
    function currentSpanNumber() external view returns (uint256);
    function currentSprint() external view returns (uint256);
    function getBorValidators(uint256 number) external view returns (address[] memory, uint256[] memory);
    function getCurrentSpan() external view returns (uint256 number, uint256 startBlock, uint256 endBlock);
    function getInitialValidators() external view returns (address[] memory, uint256[] memory);
    function getNextSpan() external view returns (uint256 number, uint256 startBlock, uint256 endBlock);
    function getProducersTotalStakeBySpan(uint256 span) external view returns (uint256);
    function getSpan(uint256 span) external view returns (uint256 number, uint256 startBlock, uint256 endBlock);
    function getSpanByBlock(uint256 number) external view returns (uint256);
    function getStakePowerBySigs(uint256 span, bytes32 dataHash, bytes memory sigs) external view returns (uint256);
    function getValidatorBySigner(uint256 span, address signer) external view returns (Validator memory result);
    function getValidators() external view returns (address[] memory, uint256[] memory);
    function getValidatorsTotalStakeBySpan(uint256 span) external view returns (uint256);
    function innerNode(bytes32 left, bytes32 right) external pure returns (bytes32);
    function isCurrentProducer(address signer) external view returns (bool);
    function isCurrentValidator(address signer) external view returns (bool);
    function isProducer(uint256 span, address signer) external view returns (bool);
    function isValidator(uint256 span, address signer) external view returns (bool);
    function leafNode(bytes32 d) external pure returns (bytes32);
    function producers(uint256, uint256) external view returns (uint256 id, uint256 power, address signer);
    function spanNumbers(uint256) external view returns (uint256);
    function spans(uint256) external view returns (uint256 number, uint256 startBlock, uint256 endBlock);
    function validators(uint256, uint256) external view returns (uint256 id, uint256 power, address signer);
}
