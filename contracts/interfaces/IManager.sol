//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IManager {
    function updateHistoryAndReturnLockedStCeloInVoting(address beneficiary)
        external
        returns (uint256);

    function transfer(
        address from,
        address to,
        uint256 amount
    ) external;

    function getGroupsLength() external view returns (uint256);

    function getGroup(uint256 index) external view returns (address);

    function getGroups() external view returns (address[] memory);

    function groupsContain(address group) external view returns (bool);

    function getDeprecatedGroupsLength() external view returns (uint256);

    function getDeprecatedGroup(uint256 index) external view returns (address);

    function deprecatedGroupsContain(address group) external view returns (bool);

    function removeDeprecatedGroup(address group) external returns (bool);

    function toCelo(uint256 stCeloAmount) external view returns (uint256);
}
