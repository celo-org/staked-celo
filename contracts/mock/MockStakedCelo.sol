//SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @notice This is a simple ERC20 token that can stand in for StakedCelo in
 * testing. For testing purposes it:
 *           1. Allows any address to mint/burn.
 *           2. Records the last minting/burning.
 */
contract MockStakedCelo is ERC20("Staked CELO", "stCELO") {
    address public lastMintTarget;
    uint256 public lastMintAmount;
    address public lastBurnTarget;
    uint256 public lastBurnAmount;

    function mint(address to, uint256 amount) external {
        lastMintTarget = to;
        lastMintAmount = amount;
        _mint(to, amount);
    }

    function getLastMinting() external view returns (address, uint256) {
        return (lastMintTarget, lastMintAmount);
    }

    function burn(address from, uint256 amount) external {
        lastBurnTarget = from;
        lastBurnAmount = amount;
        _burn(from, amount);
    }
}