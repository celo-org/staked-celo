//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";
import "./interfaces/IManager.sol";

// import "hardhat/console.sol";

/**
 * @title An ERC-20 token that is a fungible and transferrable representation
 * of reward-earning voted LockedGold (i.e. locked CELO).
 */
contract StakedCelo is ERC20Upgradeable, UUPSOwnableUpgradeable, Managed, UsingRegistryUpgradeable {
    mapping(address => uint256) private _lockedBalances;

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
    function initialize(
        address _manager,
        address _owner,
        address _registry
    ) external initializer {
        __ERC20_init("Staked CELO", "stCELO");
        __Managed_init(_manager);
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
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
        uint256 lockedBalance = _lockedBalances[account];
        _lockedBalances[account] = lockedBalance + amount;
    }

    function lockedBalanceOf(address account) public view returns (uint256) {
        return _lockedBalances[account];
    }

    function lockedBalanceInVotingOf(address account) public view returns (uint256) {
        IGovernance governance = getGovernance();
        return governance.getAmountOfGoldUsedForVoting(account);
    }

    function _beforeTokenTransfer(
        address from,
        address,
        uint256 amount
    ) internal override {
        uint256 lockedBalance = _lockedBalances[from];
        if (lockedBalance > 0 && from != address(0)) {
            uint256 currentBalance = balanceOf(from);
            if (currentBalance - lockedBalance < amount) {
                IManager managerContract = IManager(manager);
                uint256 lockedStakedCeloInVoting = managerContract.getLockedStCeloInVoting(from);
                require(currentBalance - lockedStakedCeloInVoting >= amount, "Not enough stCelo");
                _lockedBalances[from] = lockedStakedCeloInVoting;
            }
        }
    }
}
