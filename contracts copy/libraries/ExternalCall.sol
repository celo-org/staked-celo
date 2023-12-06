//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "@openzeppelin/contracts/utils/Address.sol";

library ExternalCall {
    /**
     * @notice Used when destination is not a contract.
     * @param destination The invalid destination address.
     */
    error InvalidContractAddress(address destination);

    /**
     * @notice Used when an execution fails.
     */
    error ExecutionFailed();

    /**
     * @notice Executes external call.
     * @param destination The address to call.
     * @param value The CELO value to be sent.
     * @param data The data to be sent.
     * @return The call return value.
     */
    function execute(
        address destination,
        uint256 value,
        bytes memory data
    ) internal returns (bytes memory) {
        if (data.length > 0) {
            if (!Address.isContract(destination)) {
                revert InvalidContractAddress(destination);
            }
        }

        bool success;
        bytes memory returnData;
        // solhint-disable-next-line avoid-low-level-calls
        (success, returnData) = destination.call{value: value}(data);
        if (!success) {
            revert ExecutionFailed();
        }

        return returnData;
    }
}
