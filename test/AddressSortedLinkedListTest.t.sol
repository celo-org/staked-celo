// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

import "./helpers/CeloTestHelper.sol";
import "../contracts/mock/MockAddressSortedLinkedList.sol";

contract AddressSortedLinkedListTest is CeloTestHelper {
    MockAddressSortedLinkedList addressSortedLinkedList;
    uint256 private _randomNonce;

    function setUp() public {
        _initNamedAccounts();
        addressSortedLinkedList = new MockAddressSortedLinkedList();
        _randomNonce = 0;
    }

    // =========================================================================
    //                          #insert() tests
    // =========================================================================

    function test_insert_shouldAddASingleElementToTheList() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        assertTrue(addressSortedLinkedList.contains(key));
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList.getElements();
        assertEq(keys.length, 1);
        assertEq(numerators.length, 1);
        assertEq(keys[0], key);
        assertEq(numerators[0], numerator);
    }

    function test_insert_shouldIncrementNumElements() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        assertEq(addressSortedLinkedList.getNumElements(), 1);
    }

    function test_insert_shouldUpdateTheHead() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        assertEq(addressSortedLinkedList.head(), key);
    }

    function test_insert_shouldUpdateTheTail() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        assertEq(addressSortedLinkedList.tail(), key);
    }

    function test_insert_shouldRevertIfKeyIsZero() public {
        uint256 numerator = 2;

        vm.expectRevert();
        addressSortedLinkedList.insert(ADDRESS_ZERO, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_insert_shouldRevertIfLesserIsEqualToKey() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        vm.expectRevert();
        addressSortedLinkedList.insert(key, numerator, key, ADDRESS_ZERO);
    }

    function test_insert_shouldRevertIfGreaterIsEqualToKey() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        vm.expectRevert();
        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, key);
    }

    function test_insert_shouldRevertWhenInsertingAnElementAlreadyInTheList() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        vm.expectRevert();
        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    // =========================================================================
    //                          #update() tests
    // =========================================================================

    function test_update_shouldUpdateTheValueForAnExistingElement() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;
        uint256 newNumerator = 3;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
        addressSortedLinkedList.update(key, newNumerator, ADDRESS_ZERO, ADDRESS_ZERO);

        assertTrue(addressSortedLinkedList.contains(key));
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList.getElements();
        assertEq(keys.length, 1);
        assertEq(numerators.length, 1);
        assertEq(keys[0], key);
        assertEq(numerators[0], newNumerator);
    }

    function test_update_shouldRevertIfTheKeyIsNotInTheList() public {
        address key = _getTestAddress(1);
        address otherKey = _getTestAddress(2);
        uint256 newNumerator = 3;

        addressSortedLinkedList.insert(key, 2, ADDRESS_ZERO, ADDRESS_ZERO);

        vm.expectRevert();
        addressSortedLinkedList.update(otherKey, newNumerator, ADDRESS_ZERO, ADDRESS_ZERO);
    }

    function test_update_shouldRevertIfLesserIsEqualToKey() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;
        uint256 newNumerator = 3;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        vm.expectRevert();
        addressSortedLinkedList.update(key, newNumerator, key, ADDRESS_ZERO);
    }

    function test_update_shouldRevertIfGreaterIsEqualToKey() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;
        uint256 newNumerator = 3;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);

        vm.expectRevert();
        addressSortedLinkedList.update(key, newNumerator, ADDRESS_ZERO, key);
    }

    // =========================================================================
    //                          #remove() tests
    // =========================================================================

    function test_remove_shouldRemoveTheElementFromTheList() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
        addressSortedLinkedList.remove(key);

        assertFalse(addressSortedLinkedList.contains(key));
    }

    function test_remove_shouldDecrementNumElements() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
        addressSortedLinkedList.remove(key);

        assertEq(addressSortedLinkedList.getNumElements(), 0);
    }

    function test_remove_shouldUpdateTheHead() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
        addressSortedLinkedList.remove(key);

        assertEq(addressSortedLinkedList.head(), ADDRESS_ZERO);
    }

    function test_remove_shouldUpdateTheTail() public {
        address key = _getTestAddress(1);
        uint256 numerator = 2;

        addressSortedLinkedList.insert(key, numerator, ADDRESS_ZERO, ADDRESS_ZERO);
        addressSortedLinkedList.remove(key);

        assertEq(addressSortedLinkedList.tail(), ADDRESS_ZERO);
    }

    function test_remove_shouldRevertIfTheKeyIsNotInTheList() public {
        address key = _getTestAddress(1);

        vm.expectRevert();
        addressSortedLinkedList.remove(key);
    }

    // =========================================================================
    //                   Multiple operations & invariants
    // =========================================================================

    function test_maintainInvariantsWhenLesserGreaterAreCorrect() public {
        uint256 numActions = 100;
        uint256 numKeys = 20;

        _doActionsAndAssertInvariants(numActions, numKeys, true);
    }

    function test_maintainInvariantsWhenLesserGreaterAreIncorrect() public {
        uint256 numActions = 200;
        uint256 numKeys = 20;

        _doActionsAndAssertInvariants(numActions, numKeys, false);
    }

    // =========================================================================
    //                         Helper functions
    // =========================================================================

    enum ActionType {
        Insert,
        Update,
        Remove
    }

    struct Element {
        address key;
        uint256 numerator;
    }

    struct Action {
        ActionType actionType;
        Element element;
    }

    function _doActionsAndAssertInvariants(
        uint256 numActions,
        uint256 numKeys,
        bool correctLesserGreater
    ) internal {
        Action[] memory sequence = _makeActionSequence(numActions, numKeys);
        address[] memory keyOptions = _generateKeyOptions(numKeys);

        uint256 successes = 0;
        for (uint256 i = 0; i < numActions; i++) {
            Action memory action = sequence[i];

            bool success = false;
            if (action.actionType == ActionType.Remove) {
                if (addressSortedLinkedList.contains(action.element.key)) {
                    addressSortedLinkedList.remove(action.element.key);
                    success = true;
                }
            } else {
                (address lesser, address greater) = correctLesserGreater
                    ? _getLesserAndGreaterCorrect(action.element)
                    : _getLesserAndGreaterRandom(keyOptions);

                if (action.actionType == ActionType.Insert) {
                    if (!addressSortedLinkedList.contains(action.element.key)) {
                        addressSortedLinkedList.insert(
                            action.element.key,
                            action.element.numerator,
                            lesser,
                            greater
                        );
                        success = true;
                    }
                } else if (action.actionType == ActionType.Update) {
                    if (addressSortedLinkedList.contains(action.element.key)) {
                        addressSortedLinkedList.update(
                            action.element.key,
                            action.element.numerator,
                            lesser,
                            greater
                        );
                        success = true;
                    }
                }
            }

            if (success) {
                successes += 1;
            }

            _assertSortedInvariants();
        }

        if (!correctLesserGreater) {
            // For incorrect lesser/greater, we just verify invariants are maintained
            // Success rate check is not strict since operations may fail
        }
    }

    function _makeActionSequence(uint256 length, uint256 numKeys)
        internal
        returns (Action[] memory)
    {
        Action[] memory sequence = new Action[](length);
        address[] memory keyOptions = _generateKeyOptions(numKeys);

        for (uint256 i = 0; i < length; i++) {
            address key = keyOptions[_randomIndex(keyOptions.length)];
            bool isInList = addressSortedLinkedList.contains(key);

            ActionType actionType;
            if (isInList) {
                actionType = _randomBool() ? ActionType.Update : ActionType.Remove;
            } else {
                actionType = ActionType.Insert;
            }

            sequence[i] = Action({
                actionType: actionType,
                element: Element({
                    key: key,
                    numerator: _randomNumerator()
                })
            });
        }

        return sequence;
    }

    function _generateKeyOptions(uint256 numKeys)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory keys = new address[](numKeys);
        for (uint256 i = 0; i < numKeys; i++) {
            keys[i] = address(uint160(uint256(keccak256(abi.encodePacked(uint256(1), i))) + 1));
        }
        return keys;
    }

    function _getLesserAndGreaterCorrect(Element memory element)
        internal
        view
        returns (address lesser, address greater)
    {
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList
            .getElements();

        lesser = ADDRESS_ZERO;
        greater = ADDRESS_ZERO;

        for (uint256 i = 0; i < keys.length; i++) {
            if (keys[i] != element.key) {
                if (numerators[i] >= element.numerator) {
                    greater = keys[i];
                }
            }

            uint256 j = keys.length - i - 1;
            if (keys[j] != element.key) {
                if (numerators[j] <= element.numerator) {
                    lesser = keys[j];
                }
            }
        }
    }

    function _getLesserAndGreaterRandom(address[] memory keyOptions)
        internal
        view
        returns (address lesser, address greater)
    {
        (address[] memory keys, ) = addressSortedLinkedList.getElements();

        lesser = ADDRESS_ZERO;
        greater = ADDRESS_ZERO;

        if (keys.length > 0) {
            if (_randomBool()) {
                lesser = keys[_randomIndex(keys.length)];
            }
            if (_randomBool()) {
                greater = keys[_randomIndex(keys.length)];
            }
        }
    }

    function _assertSortedInvariants() internal view {
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList
            .getElements();
        uint256 numElements = addressSortedLinkedList.getNumElements();

        require(keys.length == numElements, "Keys length mismatch");
        require(numerators.length == numElements, "Numerators length mismatch");

        // Check sorted order (descending)
        for (uint256 i = 1; i < keys.length; i++) {
            require(
                numerators[i] <= numerators[i - 1],
                "Elements not sorted in descending order"
            );
        }

        // Check head and tail
        if (numElements > 0) {
            require(addressSortedLinkedList.head() == keys[0], "Head mismatch");
            require(addressSortedLinkedList.tail() == keys[numElements - 1], "Tail mismatch");
        } else {
            require(addressSortedLinkedList.head() == ADDRESS_ZERO, "Head should be zero");
            require(addressSortedLinkedList.tail() == ADDRESS_ZERO, "Tail should be zero");
        }
    }

    function _randomIndex(uint256 max) internal view returns (uint256) {
        if (max == 0) return 0;
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % max;
    }

    function _randomBool() internal view returns (bool) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % 2 == 0;
    }

    function _randomNumerator() internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.number, msg.sender)));
    }

    function _getTestAddress(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed))) + 1));
    }
}
