import { NULL_ADDRESS } from "@celo/contractkit";
import { expect } from "chai";
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
});
