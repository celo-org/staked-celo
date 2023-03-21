//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface ILockedGold {
    function lock() external payable;

    function incrementNonvotingAccountBalance(address, uint256) external;

    function unlock(uint256) external;

    function relock(uint256, uint256) external;

    function withdraw(uint256) external;

    function slash(
        address account,
        uint256 penalty,
        address reporter,
        uint256 reward,
        address[] calldata lessers,
        address[] calldata greaters,
        uint256[] calldata indices
    ) external;

    function decrementNonvotingAccountBalance(address, uint256) external;

    function unlockingPeriod() external view returns (uint256);

    function getAccountTotalLockedGold(address) external view returns (uint256);

    function getTotalLockedGold() external view returns (uint256);

    function getPendingWithdrawal(address, uint256) external view returns (uint256, uint256);

    function getSlashingWhitelist() external view returns (bytes32[] memory);

    function getPendingWithdrawals(address)
        external
        view
        returns (uint256[] memory, uint256[] memory);

    function getTotalPendingWithdrawals(address) external view returns (uint256);

    function isSlasher(address) external view returns (bool);

    function owner() external view returns (address);

    function getAccountNonvotingLockedGold(address account) external view returns (uint256);
}
