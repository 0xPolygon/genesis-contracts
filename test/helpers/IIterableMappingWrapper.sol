// SPDX-License-Identifier: UNLICENSED
pragma solidity >0.5.0;

struct IndexValue {
    uint256 keyIndex;
    bool value;
}

struct KeyFlag {
    uint256 key;
    bool deleted;
}

interface IIterableMappingWrapper {
    function $mapData(uint256 a) external returns (IndexValue memory);
    function $mapKeys(uint256 a) external returns (KeyFlag memory);
    function $mapSize() external returns (uint256);
    function contains(uint256 key) external view returns (bool);
    function get(uint256 keyIndex) external view returns (uint256 key, bool value);
    function insert(uint256 key, bool value) external returns (bool replaced);
    function next(uint256 keyIndex) external view returns (uint256 r_keyIndex);
    function remove(uint256 key) external returns (bool success);
    function start() external view returns (uint256 keyIndex);
    function valid(uint256 keyIndex) external view returns (bool);
}
