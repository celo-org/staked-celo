// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/math/Math.sol";

import "./common/UsingRegistryUpgradeable.sol";
import "./common/UUPSOwnableUpgradeable.sol";

import "./interfaces/IManager.sol";
import "./interfaces/IStakedCelo.sol";
import "./interfaces/IAccount.sol";
import "./interfaces/ISpecificGroupStrategy.sol";

contract GroupHealth is UUPSOwnableUpgradeable, UsingRegistryUpgradeable {
    /**
     * @notice An instance of the StakedCelo contract for the StakedCelo protocol.
     */
    IStakedCelo public stakedCelo;

    /**
     * @notice An instance of the Account contract for the StakedCelo protocol.
     */
    IAccount public account;

    /**
     * @notice An instance of the specificGroupStrategy contract for the StakedCelo protocol.
     */
    ISpecificGroupStrategy public specificGroupStrategy;

    /**
     * @notice An instance of the Manager contract for the StakedCelo protocol.
     */
    IManager public manager;

    /**
     * @notice Used when a group does not meet the validator group health requirements.
     * @param group The group's address.
     */
    error GroupNotEligible(address group);

    /**
     * @notice Used when rebalancing to not active nor allowed group.
     * @param group The group's address.
     */
    error InvalidToGroup(address group);

    /**
     * @notice Used when rebalancing from address(0) group.
     * @param group The group's address.
     */
    error InvalidFromGroup(address group);

    /**
     * @notice Used when rebalancing and fromGroup doesn't have any extra Celo.
     * @param group The group's address.
     * @param realCelo The real Celo value.
     * @param expectedCelo The expected Celo value.
     */
    error RebalanceNoExtraCelo(address group, uint256 realCelo, uint256 expectedCelo);

    /**
     * @notice Used when rebalancing and toGroup has enough Celo.
     * @param group The group's address.
     * @param realCelo The real Celo value.
     * @param expectedCelo The expected Celo value.
     */
    error RebalanceEnoughCelo(address group, uint256 realCelo, uint256 expectedCelo);

    /**
     * @notice Initialize the contract with registry and owner.
     * @param _registry The address of the Celo registry.
     * @param _owner The address of the contract owner.
     */
    function initialize(address _registry, address _owner) external initializer {
        _transferOwnership(_owner);
        __UsingRegistry_init(_registry);
    }

    /**
     * @notice Set this contract's dependencies in the StakedCelo system.
     * @dev Manager, Account and StakedCelo all reference each other
     * so we need a way of setting these after all contracts are
     * deployed and initialized.
     * @param _stakedCelo the address of the StakedCelo contract.
     * @param _account The address of the Account contract.
     * @param _specificGroupStrategy The address of the SpecificGroupStrategy contract.
     * @param _manager The address of the Manager contract.
     */
    function setDependencies(
        address _stakedCelo,
        address _account,
        address _specificGroupStrategy,
        address _manager
    ) external onlyOwner {
        require(_stakedCelo != address(0), "StakedCelo null");
        require(_account != address(0), "Account null");
        require(_specificGroupStrategy != address(0), "SpecificGroupStrategy null");
        require(_manager != address(0), "Manager null");

        stakedCelo = IStakedCelo(_stakedCelo);
        account = IAccount(_account);
        specificGroupStrategy = ISpecificGroupStrategy(_specificGroupStrategy);
        manager = IManager(_manager);
    }

    /**
     * @notice Checks if a group meets the validator group health requirements.
     * @param group The group to check for.
     * @return Whether or not the group is valid.
     */
    function isValidGroup(address group) public view returns (bool) {
        IValidators validators = getValidators();

        // add check if group is !registered
        if (!validators.isValidatorGroup(group)) {
            return false;
        }

        (address[] memory members, , , , , uint256 slashMultiplier, ) = validators
            .getValidatorGroup(group);

        // check if group has no members
        if (members.length == 0) {
            return false;
        }
        // check for recent slash
        if (slashMultiplier < 10**24) {
            return false;
        }
        // check that at least one member is elected.
        for (uint256 i = 0; i < members.length; i++) {
            if (isGroupMemberElected(members[i])) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Returns expected Celo amount voted for by Account contract
     * vs actual amount voted for by Acccount contract
     * @param group The group.
     */
    function getExpectedAndRealCeloForGroup(address group) public view returns (uint256, uint256) {
        bool isSpecificGroupStrategy = specificGroupStrategy.isSpecificGroupStrategy(group);
        bool isActiveGroup = manager.groupsContain(group);
        uint256 realCelo = account.getCeloForGroup(group);

        if (!isSpecificGroupStrategy && !isActiveGroup) {
            return (0, realCelo);
        }

        if (isSpecificGroupStrategy && !isActiveGroup) {
            return (
                manager.toCelo(specificGroupStrategy.getTotalStCeloVotesForStrategy(group)),
                realCelo
            );
        }

        if (!isSpecificGroupStrategy && isActiveGroup) {
            uint256 stCeloSupply = stakedCelo.totalSupply();
            uint256 stCeloInDefaultStrategy = stCeloSupply -
                specificGroupStrategy.getTotalStCeloInSpecificGroupStrategies();
            uint256 supposedStCeloInActiveGroup = stCeloInDefaultStrategy /
                manager.getGroupsLength();

            return (manager.toCelo(supposedStCeloInActiveGroup), realCelo);
        }

        if (isSpecificGroupStrategy && isActiveGroup) {
            uint256 stCeloSupply = stakedCelo.totalSupply();
            uint256 stCeloInDefaultStrategy = stCeloSupply -
                specificGroupStrategy.getTotalStCeloInSpecificGroupStrategies();
            uint256 supposedStCeloInActiveGroup = stCeloInDefaultStrategy /
                manager.getGroupsLength();
            uint256 supposedstCeloInSpecificGroupStrategy = specificGroupStrategy
                .getTotalStCeloVotesForStrategy(group);

            return (
                manager.toCelo(supposedStCeloInActiveGroup + supposedstCeloInSpecificGroupStrategy),
                realCelo
            );
        }

        revert GroupNotEligible(group);
    }

    /**
     * @notice Rebalances Celo between groups that have incorrect Celo-stCelo ratio.
     * FromGroup is required to have more Celo than it should and ToGroup needs
     * to have less Celo than it should.
     * @param fromGroup The from group.
     * @param toGroup The to group.
     */
    function rebalance(address fromGroup, address toGroup)
        public
        view
        returns (
            address[] memory fromGroups,
            address[] memory toGroups,
            uint256[] memory fromVotes,
            uint256[] memory toVotes
        )
    {
        uint256 expectedFromCelo;
        uint256 realFromCelo;

        if (
            !manager.groupsContain(toGroup) &&
            !specificGroupStrategy.isSpecificGroupStrategy(toGroup)
        ) {
            // rebalancinch to deprecated/non-existant group is not allowed
            revert InvalidToGroup(toGroup);
        }

        if (fromGroup == address(0)) {
            revert InvalidFromGroup(fromGroup);
        }

        (expectedFromCelo, realFromCelo) = getExpectedAndRealCeloForGroup(fromGroup);

        if (realFromCelo <= expectedFromCelo) {
            // fromGroup needs to have more Celo than it should
            revert RebalanceNoExtraCelo(fromGroup, realFromCelo, expectedFromCelo);
        }

        uint256 expectedToCelo;
        uint256 realToCelo;

        (expectedToCelo, realToCelo) = getExpectedAndRealCeloForGroup(toGroup);

        if (realToCelo >= expectedToCelo) {
            // toGroup needs to have less Celo than it should
            revert RebalanceEnoughCelo(toGroup, realToCelo, expectedToCelo);
        }

        fromGroups = new address[](1);
        toGroups = new address[](1);
        fromVotes = new uint256[](1);
        toVotes = new uint256[](1);

        fromGroups[0] = fromGroup;
        fromVotes[0] = Math.min(realFromCelo - expectedFromCelo, expectedToCelo - realToCelo);

        toGroups[0] = toGroup;
        toVotes[0] = fromVotes[0];
    }

    /**
     * @notice Checks if a group member is elected.
     * @param groupMember The member of the group to check election status for.
     * @return Whether or not the group member is elected.
     */
    function isGroupMemberElected(address groupMember) private view returns (bool) {
        IElection election = getElection();

        address[] memory electedValidatorSigners = election.electValidatorSigners();

        for (uint256 i = 0; i < electedValidatorSigners.length; i++) {
            if (electedValidatorSigners[i] == groupMember) {
                return true;
            }
        }

        return false;
    }
}
