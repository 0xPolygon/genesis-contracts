pragma solidity 0.8.26;

contract TestGasOracle {
  enum Mode {
    Value,
    Revert,
    Short,
    Burn
  }

  Mode public mode;
  uint256 public gasLimit;

  function set(Mode _mode, uint256 _gasLimit) external {
    mode = _mode;
    gasLimit = _gasLimit;
  }

  function getGasLimit(uint256, address, bytes calldata) external view returns (uint256) {
    if (mode == Mode.Revert) revert("TestGasOracle");
    if (mode == Mode.Short) {
      assembly {
        mstore(0, 0x1234)
        return(0, 16)
      }
    }
    if (mode == Mode.Burn) {
      while (true) {}
    }
    return gasLimit;
  }
}
