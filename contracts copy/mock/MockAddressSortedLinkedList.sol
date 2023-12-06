//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../common/linkedlists/AddressSortedLinkedList.sol";

contract MockAddressSortedLinkedList {
    using AddressSortedLinkedList for SortedLinkedList.List;

    SortedLinkedList.List private list;

    function getNumElements() external view returns (uint256) {
        return list.getNumElements();
    }

    function tail() external view returns (address) {
        return list.getTail();
    }

    function head() external view returns (address) {
        return list.getHead();
    }

    function insert(
        address key,
        uint256 value,
        address lesserKey,
        address greaterKey
    ) public {
        list.insert(key, value, lesserKey, greaterKey);
    }

    function remove(address key) public {
        list.remove(key);
    }

    function update(
        address key,
        uint256 value,
        address lesserKey,
        address greaterKey
    ) public {
        list.update(key, value, lesserKey, greaterKey);
    }

    function contains(address key) public view returns (bool) {
        return list.contains(key);
    }

    function getValue(address key) public view returns (uint256) {
        return list.getValue(key);
    }

    function getElements() public view returns (address[] memory, uint256[] memory) {
        return list.getElements();
    }

    function numElementsGreaterThan(uint256 threshold, uint256 max) public view returns (uint256) {
        return list.numElementsGreaterThan(threshold, max);
    }

    function headN(uint256 n) public view returns (address[] memory) {
        return list.headN(n);
    }

    function getKeys() public view returns (address[] memory) {
        return list.getKeys();
    }
}
