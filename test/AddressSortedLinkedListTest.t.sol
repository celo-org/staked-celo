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
        uint256 keyIndex;
        Element element;
    }

    function _doActionsAndAssertInvariants(
        uint256 numActions,
        uint256 numKeys,
        bool correctLesserGreater
    ) internal {
        address[] memory keyOptions = _generateKeyOptions(numKeys);
        Action[] memory sequence = _makeActionSequence(numActions, keyOptions);

        // Calls are only allowed to revert when the lesser/greater hints are deliberately bogus.
        bool allowFailingTx = !correctLesserGreater;

        // Expected list contents, mirrored from the calls that actually went through:
        // expectedKeys[i] tells whether keyOptions[i] should currently be in the list, and
        // expectedValues[i] the numerator it should hold.
        bool[] memory expectedKeys = new bool[](numKeys);
        uint256[] memory expectedValues = new uint256[](numKeys);
        uint256 expectedCount = 0;
        uint256 successes = 0;

        for (uint256 i = 0; i < numActions; i++) {
            Action memory action = sequence[i];
            bool success = true;

            if (action.actionType == ActionType.Remove) {
                try addressSortedLinkedList.remove(action.element.key) {
                    expectedKeys[action.keyIndex] = false;
                    expectedCount -= 1;
                } catch {
                    success = false;
                }
            } else {
                (address lesser, address greater) = correctLesserGreater
                    ? _getLesserAndGreaterCorrect(action.element)
                    : _getLesserAndGreaterRandom(keyOptions);

                if (action.actionType == ActionType.Insert) {
                    try addressSortedLinkedList.insert(
                        action.element.key, action.element.numerator, lesser, greater
                    ) {
                        expectedKeys[action.keyIndex] = true;
                        expectedValues[action.keyIndex] = action.element.numerator;
                        expectedCount += 1;
                    } catch {
                        success = false;
                    }
                } else {
                    try addressSortedLinkedList.update(
                        action.element.key, action.element.numerator, lesser, greater
                    ) {
                        expectedValues[action.keyIndex] = action.element.numerator;
                    } catch {
                        success = false;
                    }
                }
            }

            if (success) {
                successes += 1;
            } else {
                require(allowFailingTx, "Action reverted with correct lesser/greater");
            }

            _assertSortedInvariants(keyOptions, expectedKeys, expectedValues, expectedCount);
        }

        if (allowFailingTx) {
            // Bogus hints make most calls revert, but a useful share must still go through,
            // otherwise the test would be asserting invariants on an untouched list.
            // Original bound: successes / numActions >= (2 / numKeys) * 0.75, in integer math.
            require(
                successes * numKeys * 100 >= numActions * 2 * 75, "Success rate below expectation"
            );
        }
    }

    function _makeActionSequence(uint256 length, address[] memory keyOptions)
        internal
        returns (Action[] memory)
    {
        Action[] memory sequence = new Action[](length);

        // Simulated list contents while the sequence is built, so that it holds a realistic
        // mix of inserts, updates and removes instead of inserts only.
        bool[] memory listKeys = new bool[](keyOptions.length);

        for (uint256 i = 0; i < length; i++) {
            uint256 keyIndex = _randomIndex(keyOptions.length);

            ActionType actionType;
            if (listKeys[keyIndex]) {
                if (_randomBool()) {
                    actionType = ActionType.Update;
                } else {
                    actionType = ActionType.Remove;
                    listKeys[keyIndex] = false;
                }
            } else {
                actionType = ActionType.Insert;
                listKeys[keyIndex] = true;
            }

            sequence[i] = Action({
                actionType: actionType,
                keyIndex: keyIndex,
                element: Element({key: keyOptions[keyIndex], numerator: _randomNumerator()})
            });
        }

        return sequence;
    }

    function _generateKeyOptions(uint256 numKeys) internal pure returns (address[] memory) {
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
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList.getElements();

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

    /// @dev Deliberately bogus hints: each one is a coin flip between the zero address and a
    ///      random key. Hints are only picked once the list is non-empty, because on an empty
    ///      list the zero address is the correct hint and nothing could ever be inserted.
    function _getLesserAndGreaterRandom(address[] memory keyOptions)
        internal
        returns (address lesser, address greater)
    {
        (address[] memory keys,) = addressSortedLinkedList.getElements();
        lesser = ADDRESS_ZERO;
        greater = ADDRESS_ZERO;

        if (keys.length > 0) {
            if (_randomBool()) {
                lesser = _randomHintKey(keys, keyOptions);
            }
            if (_randomBool()) {
                greater = _randomHintKey(keys, keyOptions);
            }
        }
    }

    /// @dev Half of the bogus hints are a key currently in the list (so the wrong position is
    ///      what makes them bogus), half come from the whole key universe and may not be in
    ///      the list at all.
    function _randomHintKey(address[] memory keys, address[] memory keyOptions)
        internal
        returns (address)
    {
        if (_randomBool()) {
            return keyOptions[_randomIndex(keyOptions.length)];
        }
        return keys[_randomIndex(keys.length)];
    }

    function _assertSortedInvariants(
        address[] memory keyOptions,
        bool[] memory expectedKeys,
        uint256[] memory expectedValues,
        uint256 expectedCount
    ) internal view {
        (address[] memory keys, uint256[] memory numerators) = addressSortedLinkedList.getElements();
        uint256 numElements = addressSortedLinkedList.getNumElements();

        require(keys.length == numElements, "Keys length mismatch");
        require(numerators.length == numElements, "Numerators length mismatch");
        require(numElements == expectedCount, "Incorrect number of elements");

        // A key is in the list exactly when it is expected to be, holding the value of the
        // last call that touched it. Combined with the element count above, this makes the
        // list key set equal to the expected key set.
        for (uint256 j = 0; j < keyOptions.length; j++) {
            bool found = false;
            for (uint256 i = 0; i < keys.length; i++) {
                if (keys[i] == keyOptions[j]) {
                    found = true;
                    require(numerators[i] == expectedValues[j], "Values do not match");
                    break;
                }
            }
            require(found == expectedKeys[j], "Keys do not match");
        }

        // Check sorted order (descending)
        for (uint256 i = 1; i < keys.length; i++) {
            require(numerators[i] <= numerators[i - 1], "Elements not sorted in descending order");
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

    /// @dev Pseudo-random and deterministic across runs. The nonce is what makes consecutive
    ///      calls differ: block.timestamp and block.number never move inside a test.
    function _random() private returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.number, _randomNonce++)));
    }

    function _randomIndex(uint256 max) internal returns (uint256) {
        if (max == 0) return 0;
        return _random() % max;
    }

    function _randomBool() internal returns (bool) {
        return _random() % 2 == 0;
    }

    /// @dev Same magnitude as the original: a random value below 1e20.
    function _randomNumerator() internal returns (uint256) {
        return _random() % 1e20;
    }

    function _getTestAddress(uint256 seed) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(seed))) + 1));
    }
}
