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
    uint256 public totalLocked;

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
    function mint(address to, uint256 amount) public onlyManager {
        _mint(to, amount);
    }

    /**
     * @notice Burns stCELO from an address.
     * @param from The address that will have its stCELO burned.
     * @param amount The amount of stCELO to burn.
     */
    function burn(address from, uint256 amount) public onlyManager {
        _burn(from, amount);
    }

    /**
     * @notice Locks stCELO from an address.
     * @param account The address that will have its stCELO balance locked.
     * @param amount The amount of stCELO to lock.
     */
    function lockBalance(address account, uint256 amount) external onlyManager {
        uint256 lockedBalance = _lockedBalances[account];
        if (lockedBalance < amount) {
            _lockedBalances[account] = amount;
            uint256 amountToBurn = amount - lockedBalance;
            totalLocked += amountToBurn;
            burn(account, amountToBurn);
            emit Locked(account, amount);
        }
    }

    /**
     * @notice Returns stCELO locked balance.
     * @param account The address of locked stCELO balance.
     * @return The amount of locked stCELO.
     */
    function lockedBalanceOf(address account) public view returns (uint256) {
        return _lockedBalances[account];
    }

    /**
     * @notice Unlocks stCELO from an address.
     * @param account The address that will have its stCELO balance unlocked.
     */
    function unlockBalance(address account) public {
        uint256 previouslyLocked = _lockedBalances[account];
        require(previouslyLocked > 0, "No locked stCelo");
        uint256 currentlyLocked = IManager(manager).getLockedStCeloInVotingAndUpdateHistory(
            account
        );
        require(previouslyLocked >= currentlyLocked, "Not enough locked stCelo");
        if (previouslyLocked != currentlyLocked) {
            _lockedBalances[account] = currentlyLocked;
            uint256 amountToMint = previouslyLocked - currentlyLocked;
            mint(account, amountToMint);
            totalLocked -= amountToMint;
            emit Unlocked(account, previouslyLocked - _lockedBalances[account]);
        }
    }

    /**
     * @notice Returns total supply (unlocked + locked).
     * @return The total supply.
     */
    function totalSupply() public view override returns (uint256) {
        uint256 currentTotalSuply = super.totalSupply();
        return currentTotalSuply + totalLocked;
    }

    /**
     * @notice Overides stCelo locked balance.
     * @param account The address that will have its stCELO lock balance overriden.
     * @param newLockBalance The desired lock balance.
     */
    function overrideLockBalance(address account, uint256 newLockBalance) public onlyManager {
        uint256 previouslyLocked = _lockedBalances[account];
        require(previouslyLocked >= newLockBalance, "Not enough locked stCelo");
        _lockedBalances[account] = newLockBalance;
        uint256 amountToMint = previouslyLocked - newLockBalance;
        mint(account, amountToMint);
        totalLocked -= amountToMint;
        emit Unlocked(account, previouslyLocked - _lockedBalances[account]);
    }
}
