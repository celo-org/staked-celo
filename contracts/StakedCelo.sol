//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";
import "./interfaces/IManager.sol";

import "hardhat/console.sol";

/**
 * @title An ERC-20 token that is a fungible and transferrable representation
 * of reward-earning voted LockedGold (i.e. locked CELO).
 */
contract StakedCelo is ERC20Upgradeable, UUPSOwnableUpgradeable, Managed {
    mapping(address => uint256) private _lockedBalances;

    event Locked(address account, uint256 amount);
    event Unlocked(address account, uint256 amount);

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @notice Initializes the contract.
     * @param _manager The address of the Manager contract.
     * @param _owner The address to set as the owner.
     */
    function initialize(address _manager, address _owner) external initializer {
        __ERC20_init("Staked CELO", "stCELO");
        __Managed_init(_manager);
        _transferOwnership(_owner);
    }

    /**
     * @notice Mints new stCELO to an address.
     * @param to The address that will receive the new stCELO.
     * @param amount The amount of stCELO to mint.
     */
    function mint(address to, uint256 amount) external onlyManager {
        _mint(to, amount);
    }

    /**
     * @notice Burns stCELO from an address.
     * @param from The address that will have its stCELO burned.
     * @param amount The amount of stCELO to burn.
     */
    function burn(address from, uint256 amount) external onlyManager {
        _burn(from, amount);
    }

    function lockBalance(address account, uint256 amount) external onlyManager {
        require(balanceOf(account) >= amount, "Not enough stCelo to lock");
        uint256 lockedBalance = _lockedBalances[account];
        _lockedBalances[account] = Math.max(lockedBalance, amount);
        emit Locked(account, amount);
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        return _lockedBalances[account];
    }

    function _beforeTokenTransfer(
        address from,
        address,
        uint256 amount
    ) internal view override {
        uint256 lockedBalance = _lockedBalances[from];
        if (lockedBalance > 0 && from != address(0)) {
            uint256 currentBalance = balanceOf(from);
            require(currentBalance - lockedBalance >= amount, "Not enough stCelo");
        }
    }

    function unlockBalance(address account) public {
        uint256 previouslyLocked = _lockedBalances[account];
        require(previouslyLocked > 0, "No locked stCelo");
        _lockedBalances[account] = IManager(manager).getLockedStCeloInVoting(account);
        if (previouslyLocked != _lockedBalances[account]) {
            emit Unlocked(account, previouslyLocked - _lockedBalances[account]);
        }
    }

    function overrideUnlockBalance(address account, uint256 newUnlockBalance) public onlyOwner {
        _lockedBalances[account] = newUnlockBalance;
    }
}
