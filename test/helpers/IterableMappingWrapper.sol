pragma solidity ^0.5.2;

import "../../contracts/IterableMapping.sol";

pragma solidity ^0.5.11;
pragma experimental ABIEncoderV2;

contract IterableMappingWrapper {
    IterableMapping.Map internal map;

    function $mapData(uint256 a) external returns (IterableMapping.IndexValue memory) {
        return map.data[a];
    }

    function $mapKeys(uint256 a) external returns (IterableMapping.KeyFlag memory) {
        return map.keys[a];
    }

    function $mapSize() external returns (uint256) {
        return map.size;
    }

    function insert(uint256 key, bool value) public returns (bool replaced) {
        return IterableMapping.insert(map, key, value);
    }

    function remove(uint256 key) public returns (bool success) {
        return IterableMapping.remove(map, key);
    }

    function contains(uint256 key) public view returns (bool) {
        return IterableMapping.contains(map, key);
    }

    function start() public view returns (uint256 keyIndex) {
        return IterableMapping.start(map);
    }

    function valid(uint256 keyIndex) public view returns (bool) {
        return IterableMapping.valid(map, keyIndex);
    }

    function next(uint256 keyIndex) public view returns (uint256 r_keyIndex) {
        return IterableMapping.next(map, keyIndex);
    }

    function get(uint256 keyIndex) public view returns (uint256 key, bool value) {
        return IterableMapping.get(map, keyIndex);
    }
}
