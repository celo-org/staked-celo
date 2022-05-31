// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IGoldToken {
    function transfer(address to, uint256 value) external returns (bool);

    function transferWithComment(
        address to,
        uint256 value,
        string calldata comment
    ) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function increaseAllowance(address spender, uint256 value) external returns (bool);

    function decreaseAllowance(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);
}
