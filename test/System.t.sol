pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/ISystem.sol";

contract SystemTest is Test {
    ISystem internal system;

    function setUp() public {
        system = ISystem(deployCode("out/System.sol/System.0.6.12.json"));
    }

    function test_constants() public {
        assertEq(system.SYSTEM_ADDRESS(), 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
    }
}
