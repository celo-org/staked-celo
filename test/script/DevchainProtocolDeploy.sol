// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../helpers/DevchainHelper.sol";
import {IVmExtended} from "../helpers/deploy/FullTestManagerDeployHelper.sol";

import "../../contracts/StakedCelo.sol";
import "../../contracts/Vote.sol";
import "../../contracts/GroupHealth.sol";
import "../../contracts/RebasedStakedCelo.sol";
import "../../contracts/common/ERC1967Proxy.sol";

/**
 * @title DevchainProtocolDeploy
 * @notice Deploys the full StakedCelo protocol against the real Celo Registry of the
 *         devchain fixture, so that the operational task scripts can be exercised against
 *         the real Election, LockedGold and Validators contracts.
 * @dev CoreDeployHelper only offers deployCoreWithMockRegistry(), and its per contract
 *      deploy steps are private, so the same sequence (production deploy scripts 00-13) is
 *      repeated here with REGISTRY_ADDRESS and a configurable MultiSig owner set. It is not
 *      inherited either: it and DevchainHelper both derive from CeloTestHelper, and
 *      DevchainHelper's non virtual epoch overrides make that diamond unresolvable.
 */
abstract contract DevchainProtocolDeploy is DevchainHelper {
    /// @dev Minimum delay baked into the MultiSig implementation, and the delay used here.
    uint256 internal constant MULTISIG_DELAY = 3 * DAY;

    // ---- deployed protocol ----
    IMultiSig public multiSig;
    address public multiSigProxy;
    Manager public manager;
    Account public account;
    StakedCelo public stakedCelo;
    Vote public vote;
    GroupHealth public groupHealth;
    SpecificGroupStrategy public specificGroupStrategy;
    DefaultStrategy public defaultStrategy;
    RebasedStakedCelo public rebasedStakedCelo;

    /**
     * @notice Deploys the protocol with `owners` controlling the MultiSig.
     * @param owners The initial MultiSig owners.
     * @param requiredConfirmations The number of confirmations a proposal needs.
     */
    function deployProtocolOnDevchain(address[] memory owners, uint256 requiredConfirmations)
        internal
    {
        _initNamedAccounts();

        vm.startPrank(deployer);
        _deployDevchainMultiSig(owners, requiredConfirmations);
        _deployDevchainProtocolContracts();
        _wireDevchainDependencies();
        _transferDevchainOwnership();
        vm.stopPrank();
    }

    /// @dev Script 00: MultiSig implementation (via getCode, it cannot be imported) + proxy.
    function _deployDevchainMultiSig(address[] memory owners, uint256 requiredConfirmations)
        private
    {
        bytes memory creation = abi.encodePacked(
            IVmExtended(address(vm)).getCode("MultiSig.sol:MultiSig"),
            abi.encode(MULTISIG_DELAY)
        );
        address implementation;
        assembly {
            implementation := create(0, add(creation, 0x20), mload(creation))
        }
        require(implementation != ADDRESS_ZERO, "MultiSig impl deploy failed");

        ERC1967Proxy proxy = new ERC1967Proxy(
            implementation,
            abi.encodeWithSignature(
                "initialize(address[],uint256,uint256)",
                owners,
                requiredConfirmations,
                MULTISIG_DELAY
            )
        );
        multiSigProxy = address(proxy);
        multiSig = IMultiSig(multiSigProxy);
    }

    /// @dev Scripts 01-07: the protocol contracts behind ERC1967 proxies.
    function _deployDevchainProtocolContracts() private {
        manager = Manager(
            address(
                new ERC1967Proxy(
                    address(new Manager()),
                    abi.encodeWithSelector(
                        Manager.initialize.selector,
                        REGISTRY_ADDRESS,
                        deployer
                    )
                )
            )
        );
        account = Account(
            payable(
                address(
                    new ERC1967Proxy(
                        address(new Account()),
                        abi.encodeWithSelector(
                            Account.initialize.selector,
                            REGISTRY_ADDRESS,
                            address(manager),
                            deployer
                        )
                    )
                )
            )
        );
        stakedCelo = StakedCelo(
            address(
                new ERC1967Proxy(
                    address(new StakedCelo()),
                    abi.encodeWithSelector(
                        StakedCelo.initialize.selector,
                        address(manager),
                        deployer
                    )
                )
            )
        );
        _deployDevchainSupportingContracts();
    }

    /// @dev Scripts 04-07: Vote, GroupHealth and the two strategies.
    function _deployDevchainSupportingContracts() private {
        vote = Vote(
            address(
                new ERC1967Proxy(
                    address(new Vote()),
                    abi.encodeWithSelector(
                        Vote.initialize.selector,
                        REGISTRY_ADDRESS,
                        deployer,
                        address(manager)
                    )
                )
            )
        );
        groupHealth = GroupHealth(
            address(
                new ERC1967Proxy(
                    address(new GroupHealth()),
                    abi.encodeWithSelector(
                        GroupHealth.initialize.selector,
                        REGISTRY_ADDRESS,
                        multiSigProxy
                    )
                )
            )
        );
        specificGroupStrategy = SpecificGroupStrategy(
            address(
                new ERC1967Proxy(
                    address(new SpecificGroupStrategy()),
                    abi.encodeWithSelector(
                        SpecificGroupStrategy.initialize.selector,
                        deployer,
                        address(manager)
                    )
                )
            )
        );
        defaultStrategy = DefaultStrategy(
            address(
                new ERC1967Proxy(
                    address(new DefaultStrategy()),
                    abi.encodeWithSelector(
                        DefaultStrategy.initialize.selector,
                        deployer,
                        address(manager)
                    )
                )
            )
        );
    }

    /// @dev Scripts 08-11: wire the contracts together.
    function _wireDevchainDependencies() private {
        manager.setDependencies(
            address(stakedCelo),
            address(account),
            address(vote),
            address(groupHealth),
            address(specificGroupStrategy),
            address(defaultStrategy)
        );
        vote.setDependencies(address(stakedCelo), address(account));
        specificGroupStrategy.setDependencies(
            address(account),
            address(groupHealth),
            address(defaultStrategy)
        );
        defaultStrategy.setDependencies(
            address(account),
            address(groupHealth),
            address(specificGroupStrategy)
        );
    }

    /// @dev Scripts 12-13: hand ownership to the MultiSig and deploy RebasedStakedCelo.
    function _transferDevchainOwnership() private {
        account.transferOwnership(multiSigProxy);
        stakedCelo.transferOwnership(multiSigProxy);
        manager.transferOwnership(multiSigProxy);
        vote.transferOwnership(multiSigProxy);
        specificGroupStrategy.transferOwnership(multiSigProxy);
        defaultStrategy.transferOwnership(multiSigProxy);

        rebasedStakedCelo = RebasedStakedCelo(
            address(
                new ERC1967Proxy(
                    address(new RebasedStakedCelo()),
                    abi.encodeWithSelector(
                        RebasedStakedCelo.initialize.selector,
                        address(stakedCelo),
                        address(account),
                        multiSigProxy
                    )
                )
            )
        );
    }
}
