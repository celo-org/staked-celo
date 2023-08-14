//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./common/ERC20Upgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";
import "./Managed.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/IStakedCelo.sol";

/**
 * @title An ERC-20 wrapper contract that receives stCELO
 * and represents the underlying voted LockedGold in the StakedCelo system.
 * @dev This contract depends on the Account and StakedCelo contracts
 * to calculate the amount of rstCELO held by depositors.
 */
contract RebasedStakedCelo is ERC20Upgradeable, UUPSOwnableUpgradeable {
    /**
     * @notice Total amount of stCELO deposited in this contract.
     */
    uint256 public totalDeposit;

    /**
     * @notice Keyed by depositor address, the amount of stCELO deposited.
     */
    mapping(address => uint256) public stakedCeloBalance;

    /**
     * @notice An instance of the StakedCelo contract.
     */
    IStakedCelo internal stakedCelo;

    /**
     * @notice An instance of the Account contract.
     */
    IAccount internal account;

    /**
     * @notice Used when a deposit is successfuly completed.
     * @param depositor The address of the depositor.
     * @param amount The amount of stCELO deposited.
     */
    event StakedCeloDeposited(address indexed depositor, uint256 amount);

    /**
     * @notice Used when a withdrawal is successfully completed.
     * @param withdrawer The address of the withdrawer.
     * @param amount The amount of stCELO withdrawn.
     */
    event StakedCeloWithdrawn(address indexed withdrawer, uint256 amount);

    /**
     * @notice Used when the deposit amount is zero.
     */
    error ZeroAmount();

    /**
     * @notice Used when a balance is too low.
     * @param amount The amount of stCELO that is insufficient.
     */
    error InsufficientBalance(uint256 amount);

    /**
     * @notice Used when an null address is used.
     */
    error NullAddress();

    /**
     * @notice Used when deposit fails.
     * @param depositor The address of the depositor.
     * @param amount The amount of stCELO the depositor attempted to deposit.
     */
    error FailedDeposit(address depositor, uint256 amount);

    /**
     * @notice Used when withdrawal fails.
     * @param withdrawer The address of the withdrawer.
     * @param amount The amount of stCELO the withdrawer attempted to withdraw.
     */
    error FailedWithdrawal(address withdrawer, uint256 amount);

    /**
     * Used when input amount of token is greater than total token amount.
     */
    error InputLargerThanTotalAmount();

    /**
     * @notice Empty constructor for proxy implementation, `initializer` modifer ensures the
     * implementation gets initialized.
     */
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    /**
     * @notice Replaces the constructor for proxy implementation.
     * @param _stakedCelo The address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     * @param _owner The address of the contract owner.
     */
    function initialize(
        address _stakedCelo,
        address _account,
        address _owner
    ) external initializer {
        __ERC20_init("Rebased Staked CELO", "rstCELO");
        _transferOwnership(_owner);
        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
    }

    /**
     * @notice Deposit stCELO in return for rstCELO.
     * @dev Although rstCELO is never minted to any account, the rstCELO balance
     * is calculated based on the account's deposited stCELO. See `balanceOf()` function below.
     * @param stCeloAmount The Amount of stCELO to be deposited.
     */
    function deposit(uint256 stCeloAmount) external {
        if (stCeloAmount == 0) {
            revert ZeroAmount();
        }

        totalDeposit += stCeloAmount;

        stakedCeloBalance[msg.sender] += stCeloAmount;

        emit StakedCeloDeposited(msg.sender, stCeloAmount);

        if (!stakedCelo.transferFrom(msg.sender, address(this), stCeloAmount)) {
            revert FailedDeposit(msg.sender, stCeloAmount);
        }
    }

    /**
     * @notice Withdraws stCELO. This function transfers back some or all of sender's
     * previously deposited stCELO amount.
     * @param stCeloAmount The amount of stCELO to withdraw.
     */
    function withdraw(uint256 stCeloAmount) external {
        if (stCeloAmount > stakedCeloBalance[msg.sender]) {
            revert InsufficientBalance(stCeloAmount);
        }

        totalDeposit -= stCeloAmount;

        unchecked {
            stakedCeloBalance[msg.sender] -= stCeloAmount;
        }
        emit StakedCeloWithdrawn(msg.sender, stCeloAmount);

        if (!stakedCelo.transfer(msg.sender, stCeloAmount)) {
            revert FailedWithdrawal(msg.sender, stCeloAmount);
        }
    }

    /**
     * @notice Returns the storage, major, minor, and patch version of the contract.
     * @return Storage version of the contract.
     * @return Major version of the contract.
     * @return Minor version of the contract.
     * @return Patch version of the contract.
     */
    function getVersionNumber()
        external
        pure
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (1, 1, 1, 2);
    }

    /**
     * @notice Used to query the total supply of rstCELO.
     * @return The calculated total supply of rstCELO.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return toRebasedStakedCelo(totalDeposit);
    }

    /**
     * @notice Used to query the rstCELO balance of an address.
     * @param _account The address of interest.
     * @return The amount of rstCELO owned by the address.
     */
    function balanceOf(address _account) public view override returns (uint256) {
        return toRebasedStakedCelo(stakedCeloBalance[_account]);
    }

    /**
     * @notice Computes the amount of stCELO that is represented by an amount of rstCELO.
     * @param rstCeloAmount The amount of rstCELO.
     * @return The amount of stCELO represented by rstCELO.
     */
    function toStakedCelo(uint256 rstCeloAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        uint256 rstSupply = totalSupply();
        if (rstSupply < rstCeloAmount) {
            revert InputLargerThanTotalAmount();
        }

        if (stCeloSupply == 0 || celoBalance == 0) {
            return rstCeloAmount;
        }

        return (rstCeloAmount * stCeloSupply) / celoBalance;
    }

    /**
     * @notice Computes the amount of rstCELO that is represented by an amount of stCELO.
     * @param stCeloAmount The amount of stCELO.
     * @return The amount of rstCELO represented by stCELO.
     */
    function toRebasedStakedCelo(uint256 stCeloAmount) public view returns (uint256) {
        uint256 stCeloSupply = stakedCelo.totalSupply();
        uint256 celoBalance = account.getTotalCelo();

        if (stCeloSupply < stCeloAmount) {
            revert InputLargerThanTotalAmount();
        }

        if (stCeloSupply == 0 || celoBalance == 0) {
            return stCeloAmount;
        }

        return (stCeloAmount * celoBalance) / stCeloSupply;
    }

    /**
     * @notice Moves `amount` of rstCELO from `sender` to `recipient`.
     * @param from The address of the sender.
     * @param to The address of the receiver.
     * @param amount The amount of rstCELO to transfer.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (from == address(0)) {
            revert NullAddress();
        }
        if (to == address(0)) {
            revert NullAddress();
        }

        uint256 fromBalance = stakedCeloBalance[from];
        uint256 equivalentStakedCeloAmount = toStakedCelo(amount);
        if (fromBalance < equivalentStakedCeloAmount) {
            revert InsufficientBalance(amount);
        }

        unchecked {
            stakedCeloBalance[from] = fromBalance - equivalentStakedCeloAmount;
        }
        stakedCeloBalance[to] += equivalentStakedCeloAmount;

        emit Transfer(from, to, amount);
    }
}
