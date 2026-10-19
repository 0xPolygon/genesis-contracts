pragma solidity 0.8.28;

// stand-in for a later per-receiver oracle, to test upgrades behind the proxy
contract TestGasOracleV2 {
  function getGasLimit(uint256, address receiver, bytes calldata) external pure returns (uint256) {
    return uint256(uint160(receiver)) % 1_000_000;
  }
}
