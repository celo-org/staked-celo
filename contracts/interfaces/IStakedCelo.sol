//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IStakedCelo {
    function totalSupply() external view returns (uint256);

    function mint(address, uint256) external;

    function burn(address, uint256) external;

    function transfer(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function lockBalance(address account, uint256 amount) external;
}
