//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IRegistry {
    function setAddressFor(string calldata, address) external;

    function getAddressForOrDie(bytes32) external view returns (address);

    function getAddressFor(bytes32) external view returns (address);

    function getAddressForStringOrDie(string calldata identifier) external view returns (address);

    function getAddressForString(string calldata identifier) external view returns (address);

    function isOneOf(bytes32[] calldata, address) external view returns (bool);
}
