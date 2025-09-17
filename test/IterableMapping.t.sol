pragma solidity 0.8.26;

import "../lib/forge-std/src/Test.sol";

import "./helpers/IIterableMappingWrapper.sol";

contract IterableMappingTest is Test {
    IIterableMappingWrapper internal iterableMappingWrapper;

    function setUp() public {
        iterableMappingWrapper = IIterableMappingWrapper(deployCode("out/IterableMappingWrapper.sol/IterableMappingWrapper.json"));
    }

    function test_insert_New() public {
        assertFalse(iterableMappingWrapper.insert(10, true));
        assertFalse(iterableMappingWrapper.insert(20, false));

        assertEq(iterableMappingWrapper.$mapSize(), 2);

        assertEq(iterableMappingWrapper.$mapData(10).keyIndex, 1);
        assertEq(iterableMappingWrapper.$mapData(10).value, true);
        assertEq(iterableMappingWrapper.$mapKeys(0).key, 10);
        assertEq(iterableMappingWrapper.$mapKeys(0).deleted, false);

        assertEq(iterableMappingWrapper.$mapData(20).keyIndex, 2);
        assertEq(iterableMappingWrapper.$mapData(20).value, false);
        assertEq(iterableMappingWrapper.$mapKeys(1).key, 20);
        assertEq(iterableMappingWrapper.$mapKeys(1).deleted, false);
    }

    function test_insert_Replaced() public {
        iterableMappingWrapper.insert(10, true);
        assertTrue(iterableMappingWrapper.insert(10, false));

        assertEq(iterableMappingWrapper.$mapSize(), 1);

        assertEq(iterableMappingWrapper.$mapData(10).keyIndex, 1);
        assertEq(iterableMappingWrapper.$mapData(10).value, false);
        assertEq(iterableMappingWrapper.$mapKeys(0).key, 10);
        assertEq(iterableMappingWrapper.$mapKeys(0).deleted, false);
    }

    function test_remove_NonExistent() public {
        assertFalse(iterableMappingWrapper.remove(10));
    }

    function test_remove() public {
        iterableMappingWrapper.insert(10, true);
        // @note Should return true.
        assertFalse(iterableMappingWrapper.remove(10));

        assertEq(iterableMappingWrapper.$mapSize(), 0);

        assertEq(iterableMappingWrapper.$mapData(10).keyIndex, 0);
        assertEq(iterableMappingWrapper.$mapData(10).value, false);
        assertEq(iterableMappingWrapper.$mapKeys(0).key, 10);
        assertEq(iterableMappingWrapper.$mapKeys(0).deleted, true);
    }

    function test_contains() public {
        assertFalse(iterableMappingWrapper.contains(10));
        iterableMappingWrapper.insert(10, true);
        assertTrue(iterableMappingWrapper.contains(10));
    }

    function test_next() public {
        assertEq(iterableMappingWrapper.next(0), 1);
        iterableMappingWrapper.insert(10, true);
        iterableMappingWrapper.insert(20, true);
        iterableMappingWrapper.insert(30, true);
        iterableMappingWrapper.remove(20);
        iterableMappingWrapper.remove(30);
        assertEq(iterableMappingWrapper.next(0), 3);
        assertEq(iterableMappingWrapper.next(1), 3);
    }

    function test_start() public {
        assertEq(iterableMappingWrapper.start(), 0);
        iterableMappingWrapper.insert(10, true);
        iterableMappingWrapper.insert(20, true);
        iterableMappingWrapper.insert(30, true);
        assertEq(iterableMappingWrapper.start(), 0);
        iterableMappingWrapper.remove(10);
        iterableMappingWrapper.remove(20);
        assertEq(iterableMappingWrapper.start(), 2);
    }

    function test_valid() public {
        assertFalse(iterableMappingWrapper.valid(0));
        iterableMappingWrapper.insert(10, true);
        assertTrue(iterableMappingWrapper.valid(0));
    }

    function test_get() public {
        iterableMappingWrapper.insert(10, true);
        (uint256 key, bool value) = iterableMappingWrapper.get(0);
        assertEq(key, 10);
        assertEq(value, true);
    }
}
