//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../DefaultStrategy.sol";

contract MockDefaultStrategy is DefaultStrategy {
    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function addToStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount) public {
        updateGroupStCelo(strategy, stCeloAmount, true);
    }

    function subtractFromStrategyTotalStCeloVotesPublic(address strategy, uint256 stCeloAmount)
        internal
    {
        updateGroupStCelo(strategy, stCeloAmount, false);
    }
}
