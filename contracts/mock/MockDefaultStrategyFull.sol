//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../DefaultStrategy.sol";

contract MockDefaultStrategyFull is DefaultStrategy {
    function addToStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount) public {
        addToStrategyTotalStCeloVotesInternal(strategy, stCeloAmount);
    }

    function subtractFromStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount)
        internal
    {
        subtractFromStrategyTotalStCeloVotesInternal(strategy, stCeloAmount);
    }

    function getLesserAndGreaterOfActiveGroupsPublic(
        address originalKey,
        uint256 newValue,
        uint256 loopLimit,
        bool withdrawal
    ) public view returns (address previous, address next) {
        (previous, next) = getLesserAndGreaterOfActiveGroups(
            originalKey,
            newValue,
            loopLimit,
            withdrawal
        );
    }
}
