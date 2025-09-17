// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.5.0;

event StateCommitted(uint256 indexed stateId, bool success);
event StateSyncReplay(uint256 indexed stateId);

interface IStateReceiver {
  function SYSTEM_ADDRESS() external view returns (address);
  function commitState(uint256 syncTime, bytes memory recordBytes) external returns (bool success);
  function lastStateId() external view returns (uint256);
  function rootSetter() external view returns (address);
  function failedStateSyncsRoot() external view returns (bytes32);
  function nullifier(bytes32) external view returns (bool);
  function failedStateSyncs(uint256) external view returns (bytes memory);
  function leafCount() external view returns (uint256);
  function replayCount() external view returns (uint256);
  function TREE_DEPTH() external view returns (uint256);

  function replayFailedStateSync(uint256 stateId) external;
  function setRootAndLeafCount(bytes32 _root, uint256 _leafCount) external;
  function replayHistoricFailedStateSync(
    bytes32[16] calldata proof,
    uint256 leafIndex,
    uint256 stateId,
    address receiver,
    bytes calldata data
  ) external;
}
