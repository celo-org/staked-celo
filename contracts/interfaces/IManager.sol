//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IManager {
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        returns (uint256);

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external;

    function transferBetweenStrategies(
        address fromStrategy,
        address toStrategy,
        uint256 stCeloAmount
    ) external;

    function toCelo(uint256 stCeloAmount) external view returns (uint256);

    function toStakedCelo(uint256 celoAmount) external view returns (uint256);
}
