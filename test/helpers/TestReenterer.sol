pragma solidity 0.8.26;

contract TestReenterer {
  uint256 public reenterCount;

  function onStateReceive(uint256 id, bytes calldata _data) external {
    if (reenterCount++ == 0) {
      (bool success, bytes memory ret) = msg.sender.call(abi.encodeWithSignature("replayFailedStateSync(uint256)", id));
      // bubble up revert for tests
      if (!success) {
        assembly {
          revert(add(ret, 0x20), mload(ret))
        }
      }
    }
  }
}
