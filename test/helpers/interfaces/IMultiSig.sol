// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

// Minimal interface for MultiSig methods used in test helpers.
// Avoids importing MultiSig.sol directly to prevent Initializable
// name collision between OZ contracts and OZ contracts-upgradeable.
interface IMultiSig {
    function submitProposal(
        address[] calldata destinations,
        uint256[] calldata values,
        bytes[] calldata payloads
    ) external returns (uint256 proposalId);
    function scheduleProposal(uint256 proposalId) external;
    function executeProposal(uint256 proposalId) external;
    function delay() external view returns (uint256);
    function required() external view returns (uint256);
    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
    function proposalCount() external view returns (uint256);
}
