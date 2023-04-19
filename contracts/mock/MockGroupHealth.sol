//SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "../GroupHealth.sol";

contract MockGroupHealth is GroupHealth {
    mapping(uint256 => address) public electedValidators;
    uint256 public numberOfValidators;

    function setElectedValidator(uint256 index, address validator) public {
        if (electedValidators[index] == address(0) && validator != address(0)) {
            numberOfValidators++;
        } else if (electedValidators[index] != address(0) && validator == address(0)) {
            numberOfValidators--;
        }

        electedValidators[index] = validator;
    }

    /**
     * @notice We need to override this method since Ganache
     * doesn't support Celo pre-compiles.
     */
    function validatorSignerAddressFromCurrentSet(uint256 index)
        internal
        view
        override
        returns (address)
    {
        return electedValidators[index];
    }

    /**
     * @notice We need to override this method since Ganache
     * doesn't support Celo pre-compiles.
     */
    function numberValidatorsInCurrentSet() internal view override returns (uint256) {
        return numberOfValidators;
    }
}
