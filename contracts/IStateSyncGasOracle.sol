pragma solidity >0.5.11;

// IStateSyncGasOracle returns the gas StateReceiver forwards to a state sync receiver
interface IStateSyncGasOracle {
  function getGasLimit(uint256 stateId, address receiver, bytes calldata data) external view returns (uint256);
}
