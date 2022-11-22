//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./common/ERC20Upgradeable.sol";
import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";
import "./interfaces/IManager.sol";

/**
 * @title An ERC-20 token that is a fungible and transferrable representation
 * of reward-earning voted LockedGold (i.e. locked CELO).
 */
contract StakedCelo is ERC20Upgradeable, UUPSOwnableUpgradeable, Managed {
    mapping(address => uint256) private _lockedBalances;

    /**
     * @notice Emitted when stCelo is locked.
     * @param account The owner of locked stCelo.
     * @param amount The amount of locked stCelo.
     */
    event Locked(address account, uint256 amount);

    /**
     * @notice Emitted when stCelo is inlocked.
     * @param account The owner of unlocked stCelo.
     * @param amount The amount of unlocked stCelo.
     */
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

    /**
     * @notice Locks vote stCELO from an address.
     * @param account The address that will have its stCELO balance locked.
     * @param amount The amount of stCELO to lock.
     */
    function lockVoteBalance(address account, uint256 amount) external onlyManager {
        uint256 lockedBalance = _lockedBalances[account];
        if (lockedBalance < amount) {
            _lockedBalances[account] = amount;
            uint256 amountToSubtract = amount - lockedBalance;
            uint256 accountBalance = balanceOf(account);
            require(accountBalance >= amountToSubtract, "Not enough locked stCelo");
            unchecked {
                _balances[account] = accountBalance - amountToSubtract;
            }
            emit Locked(account, amount);
        }
    }

    /**
     * @notice Returns vote stCELO locked balance.
     * @param account The address of locked stCELO balance.
     * @return The amount of locked stCELO.
     */
    function lockedVoteBalanceOf(address account) public view returns (uint256) {
        return _lockedBalances[account];
    }

    /**
     * @notice Unlocks vote stCELO from an address.
     * @param beneficiary The address that will have its stCELO balance unlocked.
     */
    function unlockVoteBalance(address beneficiary) public {
        uint256 previouslyLocked = _lockedBalances[beneficiary];
        require(previouslyLocked > 0, "No locked stCelo");
        uint256 currentlyLocked = IManager(manager).updateHistoryAndReturnLockedStCeloInVoting(
            beneficiary
        );
        require(previouslyLocked > currentlyLocked, "Nothing to unlock");

        _lockedBalances[beneficiary] = currentlyLocked;
        uint256 amountToAdd = previouslyLocked - currentlyLocked;
        _balances[beneficiary] += amountToAdd;
        emit Unlocked(beneficiary, previouslyLocked - _lockedBalances[beneficiary]);
    }

    /**
     * @notice Overides vote stCelo locked balance.
     * @param account The address that will have its stCELO lock balance overriden.
     * @param newLockBalance The desired lock balance.
     */
    function overrideVoteLockBalance(address account, uint256 newLockBalance) public onlyManager {
        uint256 previouslyLocked = _lockedBalances[account];
        require(previouslyLocked >= newLockBalance, "Not enough locked stCelo");
        _lockedBalances[account] = newLockBalance;
        uint256 amountToAdd = previouslyLocked - newLockBalance;
        _balances[account] += amountToAdd;
        emit Unlocked(account, previouslyLocked - _lockedBalances[account]);
    }
}
