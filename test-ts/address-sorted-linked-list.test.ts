import { NULL_ADDRESS } from "@celo/contractkit";
import BigNumberJs from "bignumber.js";
import { expect } from "chai";
import { BigNumber } from "ethers";
import hre from "hardhat";
import { MockAddressSortedLinkedList__factory } from "../typechain-types/factories/MockAddressSortedLinkedList__factory";
import { MockAddressSortedLinkedList } from "../typechain-types/MockAddressSortedLinkedList";
import { resetNetwork } from "./utils";

after(() => {
  hre.kit.stop();
});

describe("AddressSortedLinkedList", () => {
  let addressSortedLinkedList: MockAddressSortedLinkedList;
  let accounts: string[] = [];

  before(async () => {
    try {
      await resetNetwork();
    } catch (error) {
      console.error(error);
    }
  });

  beforeEach(async () => {
    const Lib = await hre.ethers.getContractFactory("AddressSortedLinkedList");
    const lib = await Lib.deploy();
    await lib.deployed();

    const addressSortedLinkedListFactory: MockAddressSortedLinkedList__factory =
      (await hre.ethers.getContractFactory("MockAddressSortedLinkedList", {
        libraries: {
          AddressSortedLinkedList: lib.address,
        },
      })) as MockAddressSortedLinkedList__factory;
    addressSortedLinkedList = await addressSortedLinkedListFactory.deploy();
    accounts = await hre.web3.eth.getAccounts();
  });

  describe("#insert()", () => {
    let key: string;
    const numerator = 2;

    beforeEach(async () => {
      key = accounts[9];
    });

    it("should add a single element to the list", async () => {
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
      expect(await addressSortedLinkedList.contains(key)).to.be.true;
      const [keys, numerators] = await addressSortedLinkedList.getElements();
      expect(keys.length).to.eq(1);
      expect(numerators.length).to.eq(1);
      expect(keys[0]).to.eq(key);
      expect(numerators[0].toNumber()).to.eq(numerator);
    });

    it("should increment numElements", async () => {
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
      expect((await addressSortedLinkedList.getNumElements()).toNumber()).to.eq(1);
    });

    it("should update the head", async () => {
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
      expect(await addressSortedLinkedList.head()).to.eq(key);
    });

    it("should update the tail", async () => {
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
      expect(await addressSortedLinkedList.tail()).to.eq(key);
    });

    it("should revert if key is 0", async () => {
      await expect(
        addressSortedLinkedList.insert(NULL_ADDRESS, numerator, NULL_ADDRESS, NULL_ADDRESS)
      ).revertedWith("");
    });

    it("should revert if lesser is equal to key", async () => {
      await expect(addressSortedLinkedList.insert(key, numerator, key, NULL_ADDRESS)).revertedWith(
        ""
      );
    });

    it("should revert if greater is equal to key", async () => {
      await expect(addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, key)).revertedWith(
        ""
      );
    });

    describe("when an element is already in the list", () => {
      beforeEach(async () => {
        await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
      });

      it("should revert when inserting an element already in the list", async () => {
        await expect(
          addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS)
        ).revertedWith("");
      });
    });
  });

  describe("#update()", () => {
    let key: string;
    const numerator = 2;
    const newNumerator = 3;
    beforeEach(async () => {
      key = accounts[9];
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
    });

    it("should update the value for an existing element", async () => {
      await addressSortedLinkedList.update(key, newNumerator, NULL_ADDRESS, NULL_ADDRESS);
      expect(await addressSortedLinkedList.contains(key)).to.be.true;
      const [keys, numerators] = await addressSortedLinkedList.getElements();
      expect(keys.length).to.eq(1);
      expect(numerators.length).to.eq(1);
      expect(keys[0]).to.eq(key);
      expect(numerators[0].toNumber()).to.eq(newNumerator);
    });

    it("should revert if the key is not in the list", async () => {
      await expect(
        addressSortedLinkedList.update(accounts[8], newNumerator, NULL_ADDRESS, NULL_ADDRESS)
      ).revertedWith("");
    });

    it("should revert if lesser is equal to key", async () => {
      await expect(
        addressSortedLinkedList.update(key, newNumerator, key, NULL_ADDRESS)
      ).revertedWith("");
    });

    it("should revert if greater is equal to key", async () => {
      await expect(
        addressSortedLinkedList.update(key, newNumerator, NULL_ADDRESS, key)
      ).revertedWith("");
    });
  });

  describe("#remove()", () => {
    let key: string;
    const numerator = 2;
    beforeEach(async () => {
      key = accounts[9];
      await addressSortedLinkedList.insert(key, numerator, NULL_ADDRESS, NULL_ADDRESS);
    });

    it("should remove the element from the list", async () => {
      await addressSortedLinkedList.remove(key);
      expect(await addressSortedLinkedList.contains(key)).to.be.false;
    });

    it("should decrement numElements", async () => {
      await addressSortedLinkedList.remove(key);
      expect((await addressSortedLinkedList.getNumElements()).toNumber()).to.eq(0);
    });

    it("should update the head", async () => {
      await addressSortedLinkedList.remove(key);
      expect(await addressSortedLinkedList.head()).to.eq(NULL_ADDRESS);
    });

    it("should update the tail", async () => {
      await addressSortedLinkedList.remove(key);
      expect(await addressSortedLinkedList.tail()).to.eq(NULL_ADDRESS);
    });

    it("should revert if the key is not in the list", async () => {
      await expect(addressSortedLinkedList.remove(accounts[8])).revertedWith("");
    });
  });

  describe("when there are multiple inserts, updates, and removals", () => {
    interface SortedElement {
      key: string;
      numerator: BigNumber;
    }

    // eslint-disable-next-line no-unused-vars
    enum SortedListActionType {
      // eslint-disable-next-line no-unused-vars
      Update = 1,
      // eslint-disable-next-line no-unused-vars
      Remove,
      // eslint-disable-next-line no-unused-vars
      Insert,
    }

    interface SortedListAction {
      actionType: SortedListActionType;
      element: SortedElement;
    }

    const randomElement = <A>(list: A[]): A => {
      return list[Math.floor(BigNumberJs.random().times(list.length).toNumber())];
    };

    const randomElementOrNullAddress = (list: string[]): string => {
      if (BigNumberJs.random().isLessThan(0.5)) {
        return NULL_ADDRESS;
      } else {
        return randomElement(list);
      }
    };

    const makeActionSequence = (length: number, numKeys: number): SortedListAction[] => {
      const sequence: SortedListAction[] = [];
      const listKeys: Set<string> = new Set([]);
      // @ts-ignore
      const keyOptions = Array.from({ length: numKeys }, () =>
        hre.web3.utils.randomHex(20).toLowerCase()
      );
      for (let i = 0; i < length; i++) {
        const key = randomElement(keyOptions);
        let action: SortedListActionType;
        if (listKeys.has(key)) {
          action = randomElement([SortedListActionType.Update, SortedListActionType.Remove]);
          if (action === SortedListActionType.Remove) {
            listKeys.delete(key);
          }
        } else {
          action = SortedListActionType.Insert;
          listKeys.add(key);
        }
        sequence.push({
          actionType: action,
          element: {
            key,
            numerator: BigNumber.from(BigNumberJs.random(20).shiftedBy(20).toString()),
          },
        });
      }
      return sequence;
    };

    const parseElements = (keys: string[], numerators: BigNumber[]): SortedElement[] =>
      keys.map((key, i) => ({
        key: key.toLowerCase(),
        numerator: numerators[i],
      }));

    const assertSorted = (elements: SortedElement[]) => {
      for (let i = 0; i < elements.length; i++) {
        if (i > 0) {
          expect(elements[i].numerator.lte(elements[i - 1].numerator)).eq(
            true,
            "Elements not sorted"
          );
        }
      }
    };

    const assertSortedFractionListInvariants = async (
      elementsPromise: Promise<[string[], BigNumber[]]>,
      numElementsPromise: Promise<BigNumber>,
      // medianPromise: Promise<string>,
      expectedKeys: Set<string>
    ) => {
      const [keys, numerators] = await elementsPromise;
      const elements = parseElements(keys, numerators);
      expect((await numElementsPromise).toNumber()).to.eq(
        expectedKeys.size,
        "Incorrect number of elements"
      );

      expect(elements.map((x) => x.key).sort()).to.deep.eq(
        Array.from(expectedKeys.values()).sort(),
        "keys do not match"
      );

      assertSorted(elements);
    };

    const doActionsAndAssertInvariants = async (
      numActions: number,
      numKeys: number,
      // eslint-disable-next-line no-unused-vars
      getLesserAndGreater: (element: SortedElement) => Promise<{ lesser: string; greater: string }>,
      allowFailingTx = false
    ) => {
      const sequence = makeActionSequence(numActions, numKeys);
      const listKeys: Set<string> = new Set([]);
      let successes = 0;
      for (let i = 0; i < numActions; i++) {
        const action = sequence[i];
        try {
          if (action.actionType === SortedListActionType.Remove) {
            await addressSortedLinkedList.remove(action.element.key);
            listKeys.delete(action.element.key);
          } else {
            const { lesser, greater } = await getLesserAndGreater(action.element);
            if (action.actionType === SortedListActionType.Insert) {
              await addressSortedLinkedList.insert(
                action.element.key,
                action.element.numerator,
                lesser,
                greater
              );
              listKeys.add(action.element.key);
            } else if (action.actionType === SortedListActionType.Update) {
              await addressSortedLinkedList.update(
                action.element.key,
                action.element.numerator,
                lesser,
                greater
              );
            }
          }
          successes += 1;
        } catch (e) {
          if (!allowFailingTx) {
            throw e;
          }
        }
        await assertSortedFractionListInvariants(
          addressSortedLinkedList.getElements(),
          addressSortedLinkedList.getNumElements(),
          listKeys
        );
      }
      if (allowFailingTx) {
        const expectedSuccessRate = 2.0 / numKeys;
        expect(successes / numActions).gte(expectedSuccessRate * 0.75);
      }
    };

    it("should maintain invariants when lesser, greater are correct", async () => {
      const numActions = 100;
      const numKeys = 20;
      const getLesserAndGreater = async (element: SortedElement) => {
        const [keys, numerators] = await addressSortedLinkedList.getElements();
        const elements = parseElements(keys, numerators);
        let lesser = NULL_ADDRESS;
        let greater = NULL_ADDRESS;
        const value = element.numerator;
        // Iterate from each end of the list towards the other end, saving the key with the
        // smallest value >= `value` and the key with the largest value <= `value`.
        for (let i = 0; i < elements.length; i++) {
          if (elements[i].key !== element.key.toLowerCase()) {
            if (elements[i].numerator.gte(value)) {
              greater = elements[i].key;
            }
          }
          const j = elements.length - i - 1;

          if (elements[j].key !== element.key.toLowerCase()) {
            if (elements[j].numerator.lte(value)) {
              lesser = elements[j].key;
            }
          }
        }
        return { lesser, greater };
      };
      await doActionsAndAssertInvariants(numActions, numKeys, getLesserAndGreater);
    });

    it("should maintain invariants when lesser, greater are incorrect", async () => {
      const numReports = 200;
      const numKeys = 20;
      const getRandomKeys = async () => {
        let lesser = NULL_ADDRESS;
        let greater = NULL_ADDRESS;
        const [keys, , ,] = await addressSortedLinkedList.getElements();
        if (keys.length > 0) {
          lesser = randomElementOrNullAddress(keys);
          greater = randomElementOrNullAddress(keys);
        }
        return { lesser, greater };
      };
      await doActionsAndAssertInvariants(numReports, numKeys, getRandomKeys, true);
    });
  });
});

export const assertSameAddress = (value: string, expected: string, msg?: string) => {
  expect(expected.toLowerCase()).to.eq(value.toLowerCase(), msg);
};
