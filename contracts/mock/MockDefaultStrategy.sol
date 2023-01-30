//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../DefaultStrategy.sol";

contract MockDefaultStrategy is DefaultStrategy {
    function addToStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount) public {
        addToStrategyTotalStCeloVotes(strategy, stCeloAmount);
    }

    function subtractFromStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount)
        internal
    {
        subtractFromStrategyTotalStCeloVotes(strategy, stCeloAmount);
    }
}
