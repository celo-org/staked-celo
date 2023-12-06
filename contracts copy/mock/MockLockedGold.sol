//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/ILockedGold.sol";

/**
 * @title A mock LockedGold for testing.
 */
contract MockLockedGold is ILockedGold {
    using SafeMath for uint256;

    struct Authorizations {
        address validator;
        address voter;
    }

    mapping(address => uint256) public accountTotalLockedGold;
    mapping(address => uint256) public nonvotingAccountBalance;
    mapping(address => address) public authorizedValidators;
    mapping(address => address) public authorizedBy;
    uint256 private totalLockedGold;
    mapping(address => bool) public slashingWhitelist;
    // bool private returnVal;
    uint256 public unlockingPeriod;

    function incrementNonvotingAccountBalance(address account, uint256 value) external {
        nonvotingAccountBalance[account] = nonvotingAccountBalance[account].add(value);
    }

    function setAccountTotalLockedGold(address account, uint256 value) external {
        accountTotalLockedGold[account] = value;
    }

    function setTotalLockedGold(uint256 value) external {
        totalLockedGold = value;
    }

    function lock() external payable {
        accountTotalLockedGold[msg.sender] = accountTotalLockedGold[msg.sender].add(msg.value);
    }

    function unlock(uint256 value) external {
        accountTotalLockedGold[msg.sender] = accountTotalLockedGold[msg.sender].sub(value);
    }

    function relock(uint256 index, uint256 value) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function withdraw(uint256 index) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function slash(
        address account,
        uint256 penalty,
        address,
        uint256,
        address[] calldata,
        address[] calldata,
        uint256[] calldata
    ) external {
        accountTotalLockedGold[account] = accountTotalLockedGold[account].sub(penalty);
    }

    function addSlasher(string calldata slasherIdentifier) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function removeSlasher(string calldata slasherIdentifier) external {
        // solhint-disable-previous-line no-empty-blocks
    }

    function isSlasher(address slasher) external view returns (bool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPendingWithdrawals(address)
        external
        view
        returns (uint256[] memory, uint256[] memory)
    {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPendingWithdrawal(address, uint256) external view returns (uint256, uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getTotalPendingWithdrawals(address) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getSlashingWhitelist() external view returns (bytes32[] memory) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getAccountNonvotingLockedGold(address account) external view returns (uint256) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getAccountTotalLockedGold(address account) external view returns (uint256) {
        return accountTotalLockedGold[account];
    }

    function getTotalLockedGold() external view returns (uint256) {
        return totalLockedGold;
    }

    function decrementNonvotingAccountBalance(address account, uint256 value) public {
        nonvotingAccountBalance[account] = nonvotingAccountBalance[account].sub(value);
    }

    function owner() public view virtual returns (address) {
        // solhint-disable-previous-line no-empty-blocks
    }
}
