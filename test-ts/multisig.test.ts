import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, BigNumberish, Signer } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import hre, { ethers } from "hardhat";
import { MultiSig } from "../typechain-types/MultiSig";
import { ADDRESS_ZERO, DAY, randomSigner, timeTravel } from "./utils";

/**
 * Invokes the multisig's submitProposal, waits for the confirmation event
 * and returns the generated proposalId.
 * @param multiSig The multisig contract.
 * @param destinations The addresses at which the proposal is target at.
 * @param values The CELO values involved in the proposal if any.
 * @param payloads The payloads of the proposal.
 * @param signer The signer which submits the proposal.
 * @returns A promise of the generated proposal ID.
 */
async function submitProposalAndWaitForConfirmationEvent(
  multiSig: MultiSig,
  destinations: string[],
  values: BigNumberish[],
  payloads: string[],
  signer: Signer
): Promise<BigNumber> {
  const tx = await multiSig.connect(signer).submitProposal(destinations, values, payloads);
  const receipt = await tx.wait();
  const event = receipt.events?.find((event) => event.event === "ProposalConfirmed");
  // @ts-ignore - proposalId not a compiled member of event.args
  const proposalId = event?.args.proposalId;

  return proposalId;
}

/**
 * Submits, fully confirms and executes a multisig proposal.
 * @param multiSig The multisig contract.
 * @param destinations The addresses at which the proposal is target at.
 * @param values The CELO values involved in the proposal if any.
 * @param payloads The payloads of the proposal.
 * @param delay The delay that must elapse to be able to execute a proposal.
 * @param signer1 The first signer which submits the proposal.
 * @param signer2 The second signer which does the second and final confirmation
 * if necessary..
 */
async function executeMultisigProposal(
  multiSig: MultiSig,
  destinations: string[],
  values: BigNumberish[],
  payloads: string[],
  delay: number,
  signer1: Signer,
  signer2: Signer
) {
  const proposalId = await submitProposalAndWaitForConfirmationEvent(
    multiSig,
    destinations,
    values,
    payloads,
    signer1
  );

  const isFullyConfirmed = await multiSig.isFullyConfirmed(proposalId);
  if (!isFullyConfirmed) {
    await multiSig.connect(signer2).confirmProposal(proposalId);
  }

  timeTravel(delay);
  await multiSig.connect(signer2).executeProposal(proposalId);
}

/**
 * Initializes the multisig contract.
 * @param owners The owners of the multisig contract.
 * @param requiredSignatures The amount of confirmations required for a proposal to be fully confirmed.
 */
async function multiSigInitialize(owners: string[], requiredSignatures: number) {
  const proxy = await hre.ethers.getContractFactory("ERC1967Proxy");
  const impl = await (await hre.ethers.getContractFactory("MultiSig")).deploy();
  return proxy.deploy(
    impl.address,
    impl.interface.encodeFunctionData("initialize", [owners, requiredSignatures])
  );
}

describe("MultiSig", () => {
  let multiSig: MultiSig;
  let owner1: SignerWithAddress;
  let owner2: SignerWithAddress;
  let nonOwner: SignerWithAddress;

  let owners: string[];
  const requiredSignatures = 2;
  const delay = 7 * DAY;

  beforeEach(async () => {
    await hre.deployments.fixture("TestMultiSig");
    multiSig = await hre.ethers.getContract("MultiSig");
    owner1 = await hre.ethers.getNamedSigner("multisigOwner0");
    owner2 = await hre.ethers.getNamedSigner("multisigOwner1");
    [nonOwner] = await randomSigner(parseUnits("100"));

    owners = [owner1.address, owner2.address];
  });

  describe("#constructor", () => {
    it("should have set the delay to 3 days", async () => {
      expect(await multiSig.minDelay()).to.deep.equal(3 * DAY);
    });
  });

  describe("#initialize", () => {
    it("should have set the owners", async () => {
      expect(await multiSig.getOwners()).to.deep.equal(owners);
    });

    it("should have set the delay", async () => {
      expect(await multiSig.delay()).to.deep.equal(delay);
    });

    it("should have set the number of required signatures for making a proposal fully confirmed", async () => {
      expect(await multiSig.required()).to.eq(requiredSignatures);
    });

    it("should not be callable again", async () => {
      await expect(multiSig.initialize(owners, requiredSignatures, 3 * DAY)).revertedWith(
        "Initializable: contract is already initialized"
      );
    });

    it("should fail if count of owners is zero", async () => {
      // XXX: There's an issue with custom errors thrown via delegateCall
      // as it happens when the proxy initializes the contract.
      // We can't match, yet, sadly.
      // https://github.com/NomicFoundation/hardhat/issues/1618
      // Should throw: InvalidRequirement(0, 10)
      await expect(multiSigInitialize([], 10)).reverted;
    });

    it("should fail if count of owners is less than required confirmations value", async () => {
      // XXX: See above...
      // Should throw: InvalidRequirement(2, 10)
      await expect(multiSigInitialize(owners, 10)).reverted;
    });

    it("should fail if required confirmations value is zero", async () => {
      // XXX: See above...
      // Should throw: InvalidRequirement(2, 0)
      await expect(multiSigInitialize(owners, 0)).reverted;
    });
  });

  describe("#fallback function", () => {
    it("when receiving CELO, emits Deposit event with correct parameters", async () => {
      const value = 100;

      await expect(await owner1.sendTransaction({ to: multiSig.address, value }))
        .to.emit(multiSig, "CeloDeposited")
        .withArgs(owner1.address, value);
    });

    it("when receiving 0 value, does not emit an event", async () => {
      await expect(await owner1.sendTransaction({ to: multiSig.address, value: 0 })).to.not.emit(
        multiSig,
        "CeloDeposited"
      );
    });
  });

  describe("#submitProposal()", () => {
    let txData: string;

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
    });

    it("should allow an owner to submit a proposal", async () => {
      const proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );

      const [destinations] = await multiSig.getProposal(proposalId);
      expect(destinations).to.deep.equal([multiSig.address]);
    });

    it("should set proposal as confirmed by original sender", async () => {
      const proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
      expect(await multiSig.isConfirmedBy(proposalId, owner1.address)).to.be.true;
    });

    it("should update the proposal count", async () => {
      await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
      expect(await multiSig.proposalCount()).to.equal(1);
    });

    it("should not allow an owner to submit a proposal to a null address", async () => {
      await expect(multiSig.submitProposal([ADDRESS_ZERO], [0], [txData])).revertedWith(
        `NullAddress()`
      );
    });

    it("should not allow a non-owner to submit a proposal", async () => {
      await expect(
        multiSig.connect(nonOwner).submitProposal([multiSig.address], [0], [txData])
      ).revertedWith(`OwnerDoesNotExist("${nonOwner.address}")`);
    });

    it("should fail to submit a proposal, if the size of the provided destinations does not match that of the values ", async () => {
      await expect(
        submitProposalAndWaitForConfirmationEvent(
          multiSig,
          [multiSig.address],
          [0, 1],
          [txData],
          owner1
        )
      ).revertedWith("ParamLengthsMismatch()");
    });

    it("should fail to submit a proposal, if the size of the provided destinations does not match that of the payloads ", async () => {
      await expect(
        submitProposalAndWaitForConfirmationEvent(
          multiSig,
          [multiSig.address],
          [0],
          [txData, txData],
          owner1
        )
      ).revertedWith("ParamLengthsMismatch()");
    });

    it("should allow an owner to submit a proposal with multiple transactions", async () => {
      const secondPayload = multiSig.interface.encodeFunctionData("changeDelay", [9 * DAY]);

      const proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address, multiSig.address],
        [0, 0],
        [txData, secondPayload],
        owner1
      );

      const [payloads] = await multiSig.getProposal(proposalId);
      expect(payloads.length).to.equal(2);
    });
  });

  describe("#confirmProposal()", () => {
    let proposalId: BigNumber;

    beforeEach(async () => {
      const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("should allow an owner to confirm a proposal", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      expect(await multiSig.isConfirmedBy(proposalId, owner2.address)).to.be.true;
    });

    it("should schedule proposal once enough confirmations have been submitted", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      expect(await multiSig.isScheduled(proposalId)).to.be.true;
    });

    it("should store correct timestamp for a scheduled proposal", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);

      const block = await ethers.provider.getBlock("latest");
      const timestamp = await multiSig.delay();
      expect(await multiSig.getTimestamp(proposalId)).to.be.equal(timestamp.add(block.timestamp));
    });

    it("should not allow an owner to confirm a proposal twice", async () => {
      await expect(multiSig.connect(owner1).confirmProposal(proposalId)).revertedWith(
        `ProposalAlreadyConfirmed(0, "${owner1.address}")`
      );
    });

    it("should not allow a non-owner to confirm a proposal", async () => {
      await expect(multiSig.connect(nonOwner).confirmProposal(proposalId)).revertedWith(
        `OwnerDoesNotExist("${nonOwner.address}")`
      );
    });
  });

  describe("#scheduleProposal()", () => {
    let proposalId: BigNumber;

    beforeEach(async () => {
      const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("should not be able to schedule a proposal twice", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await expect(multiSig.connect(owner1).scheduleProposal(proposalId)).revertedWith(
        "ProposalAlreadyScheduled(0)"
      );
    });

    it("should not be able to schedule a proposal that is not fully confirmed ", async () => {
      await expect(multiSig.connect(owner1).scheduleProposal(proposalId)).revertedWith(
        "ProposalNotFullyConfirmed(0)"
      );
    });
  });

  describe("#executeProposal()", () => {
    let proposalId: BigNumber;
    let txData: string;

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("an owner should be able to execute a proposal once time lock period has passed", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await timeTravel(delay);
      await multiSig.connect(owner2).executeProposal(proposalId);
      expect(await multiSig.getTimestamp(proposalId)).to.be.equal(1);
    });

    it("any account should be able to execute a proposal once time lock period has passed", async () => {
      const [randomAcc] = await randomSigner(parseUnits("100"));
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await timeTravel(delay);
      await multiSig.connect(randomAcc).executeProposal(proposalId);
      expect(await multiSig.getTimestamp(proposalId)).to.be.equal(1);
    });

    it("should fail to execute a proposal more than once", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await timeTravel(delay);
      await multiSig.connect(owner2).executeProposal(proposalId);
      await expect(multiSig.connect(owner2).executeProposal(proposalId)).revertedWith(
        "ProposalNotScheduled(0)"
      );
    });

    it("should fail to execute proposal when time lock period has not passed", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await expect(multiSig.connect(owner2).executeProposal(proposalId)).revertedWith(
        "ProposalTimelockNotReached(0)"
      );
    });

    it("should fail execute a proposal that is not scheduled", async () => {
      timeTravel(delay);
      await expect(multiSig.connect(owner1).executeProposal(proposalId)).revertedWith(
        "ProposalNotScheduled(0)"
      );
    });

    it("should be successfully execute a proposal with many transactions once the time lock period has passed", async () => {
      const secondPayload = multiSig.interface.encodeFunctionData("changeDelay", [9 * DAY]);
      const values = [0, 0];
      const destinations = [multiSig.address, multiSig.address];

      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData, secondPayload],
        delay,
        owner1,
        owner2
      );

      expect(await multiSig.delay()).to.be.equal(9 * DAY);
      expect(await multiSig.isOwner(nonOwner.address)).to.be.true;
    });
  });

  describe("#revokeConfirmation()", () => {
    let proposalId: BigNumber;

    beforeEach(async () => {
      const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("should allow an owner to revoke a confirmation", async () => {
      await multiSig.connect(owner1).revokeConfirmation(proposalId);
      expect(await multiSig.isConfirmedBy(proposalId, owner1.address)).to.be.false;
    });

    it("should not allow a non-owner to revoke a confirmation", async () => {
      await expect(multiSig.connect(nonOwner).revokeConfirmation(proposalId)).revertedWith(
        `OwnerDoesNotExist("${nonOwner.address}")`
      );
    });

    it("should not allow an owner to revoke before confirming", async () => {
      await expect(multiSig.connect(owner2).revokeConfirmation(proposalId)).revertedWith(
        `ProposalNotConfirmed(0, "${owner2.address}")`
      );
    });
  });

  describe("#addOwner()", () => {
    let txData: string;
    let destinations: string[];
    let values = [0];

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      destinations = [multiSig.address];
    });

    it("should allow a new owner to be added via the MultiSig", async () => {
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );
      expect(await multiSig.isOwner(nonOwner.address)).to.be.true;

      expect(await multiSig.getOwners()).to.deep.equal([
        owner1.address,
        owner2.address,
        nonOwner.address,
      ]);
    });

    it("should not allow an external account to add an owner", async () => {
      await expect(multiSig.connect(nonOwner).addOwner(nonOwner.address)).revertedWith(
        `SenderMustBeMultisigWallet("${nonOwner.address}")`
      );
    });

    it("should not allow adding the null address", async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [ADDRESS_ZERO]);
      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });

    it("should fail to add owner if max number of owners is reached", async () => {
      let payloads = [];
      values = [];
      destinations = [];

      for (let i = 0; i < 48; i++) {
        const [newOwner] = await randomSigner(parseUnits("100"));
        payloads.push(multiSig.interface.encodeFunctionData("addOwner", [newOwner.address]));
        values.push(0);
        destinations.push(multiSig.address);
      }

      // Add more owners to reach MAX_OWNER_COUNT
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        payloads,
        delay,
        owner1,
        owner2
      );

      const [newOwner] = await randomSigner(parseUnits("100"));
      destinations = [multiSig.address];
      values = [0];
      payloads = [multiSig.interface.encodeFunctionData("addOwner", [newOwner.address])];

      await expect(
        executeMultisigProposal(multiSig, destinations, values, payloads, delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });
  });

  describe("#removeOwner()", () => {
    let txData: string;
    let destinations: string[];
    const values = [0];

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("removeOwner", [owner2.address]);
      destinations = [multiSig.address];
    });

    it("should allow an owner to be removed via the MultiSig", async () => {
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );
      expect(await multiSig.isOwner(owner2.address)).to.be.false;
    });

    it("should reduce the number of required confirmations if it was equal to number of owners", async () => {
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );
      expect(await multiSig.required()).to.be.equal(1);
    });

    it("should not allow an external account to remove an owner", async () => {
      await expect(multiSig.connect(nonOwner).removeOwner(owner2.address)).revertedWith(
        `SenderMustBeMultisigWallet("${nonOwner.address}")`
      );
    });

    it("should not be able to remove the last owner", async () => {
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );

      txData = multiSig.interface.encodeFunctionData("removeOwner", [owner1.address]);
      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith(`ExecutionFailed()`);
    });
  });

  describe("#replaceOwner()", () => {
    let txData: string;
    let destinations: string[];
    const values = [0];

    beforeEach(async () => {
      destinations = [multiSig.address];
    });

    it("should allow an existing owner to be replaced by a new one via the MultiSig", async () => {
      txData = multiSig.interface.encodeFunctionData("replaceOwner", [
        owner2.address,
        nonOwner.address,
      ]);
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );

      expect(await multiSig.isOwner(nonOwner.address)).to.be.true;
      expect(await multiSig.isOwner(owner2.address)).to.be.false;
      expect(await multiSig.getOwners()).to.deep.equal([owner1.address, nonOwner.address]);
    });

    it("should not allow an external account to replace an owner", async () => {
      await expect(
        multiSig.connect(nonOwner).replaceOwner(owner2.address, nonOwner.address)
      ).revertedWith(`SenderMustBeMultisigWallet("${nonOwner.address}")`);
    });

    it("should not allow an owner to be replaced by the null address", async () => {
      txData = multiSig.interface.encodeFunctionData("replaceOwner", [
        owner2.address,
        ADDRESS_ZERO,
      ]);
      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });

    it("should not allow an owner to be replaced by an existing owner", async () => {
      txData = multiSig.interface.encodeFunctionData("replaceOwner", [
        owner1.address,
        owner2.address,
      ]);

      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });
  });

  describe("#changeRequirement()", () => {
    let txData: string;
    let destinations: string[];
    const values = [0];

    beforeEach(async () => {
      destinations = [multiSig.address];
    });

    it("should allow the requirement to be changed via the MultiSig", async () => {
      txData = multiSig.interface.encodeFunctionData("changeRequirement", [1]);
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );

      expect(await multiSig.required()).to.be.equal(1);
    });

    it("should not allow an external account to change the requirement", async () => {
      await expect(multiSig.connect(nonOwner).changeRequirement(3)).revertedWith(
        `SenderMustBeMultisigWallet("${nonOwner.address}")`
      );
    });

    it("should fail if the provided number required confirmations is more than the number of owners", async () => {
      txData = multiSig.interface.encodeFunctionData("changeRequirement", [5]);
      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });
  });

  describe("#changeDelay()", () => {
    let txData: string;
    let destinations: string[];
    const values = [0];

    beforeEach(async () => {
      destinations = [multiSig.address];
    });

    it("should allow the delay to be changed via the MultiSig", async () => {
      txData = multiSig.interface.encodeFunctionData("changeDelay", [4 * DAY]);
      await executeMultisigProposal(
        multiSig,
        destinations,
        values,
        [txData],
        delay,
        owner1,
        owner2
      );
      expect(await multiSig.delay()).to.be.equal(4 * DAY);
    });

    it("should fail to change the delay to a value less than the minimum delay", async () => {
      txData = multiSig.interface.encodeFunctionData("changeDelay", [1 * DAY]);
      await expect(
        executeMultisigProposal(multiSig, destinations, values, [txData], delay, owner1, owner2)
      ).revertedWith("ExecutionFailed()");
    });

    it("should not allow an external account to change the delay", async () => {
      await expect(multiSig.connect(nonOwner).changeDelay(4 * DAY)).revertedWith(
        `SenderMustBeMultisigWallet("${nonOwner.address}")`
      );
    });
  });

  describe("#getOwners()", () => {
    it("should return the owners", async () => {
      expect(await multiSig.getOwners()).to.deep.equal(owners);
    });
  });

  describe("#getConfirmations()", () => {
    let proposalId: BigNumber;

    beforeEach(async () => {
      const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("should return the confirmations", async () => {
      expect(await multiSig.getConfirmations(proposalId)).to.deep.equal([owner1.address]);
    });
  });

  describe("#isFullyConfirmed()", () => {
    let proposalId: BigNumber;
    let txData: string;

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
    });

    it("should return true if a proposal is fully confirmed", async () => {
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
      await multiSig.connect(owner2).confirmProposal(proposalId);
      expect(await multiSig.isFullyConfirmed(proposalId)).to.be.true;
    });

    it("should return false if a proposal is not fully confirmed", async () => {
      expect(await multiSig.isFullyConfirmed(proposalId)).to.be.false;
    });
  });

  describe("#isConfirmedBy()", () => {
    let proposalId: BigNumber;
    let txData: string;

    beforeEach(async () => {
      txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
    });

    it("should return true if a proposal is confirmed by an address", async () => {
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
      expect(await multiSig.isConfirmedBy(proposalId, owner1.address)).to.be.true;
    });

    it("should return false if a proposal is not confirmed by an address", async () => {
      expect(await multiSig.isConfirmedBy(proposalId, owner1.address)).to.be.false;
    });
  });

  describe("#isProposalTimelockReached()", () => {
    let proposalId: BigNumber;

    beforeEach(async () => {
      const txData = multiSig.interface.encodeFunctionData("addOwner", [nonOwner.address]);
      proposalId = await submitProposalAndWaitForConfirmationEvent(
        multiSig,
        [multiSig.address],
        [0],
        [txData],
        owner1
      );
    });

    it("should return true if the proposal time lock is reached", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      await timeTravel(delay);
      expect(await multiSig.isProposalTimelockReached(proposalId)).to.be.true;
    });

    it("should return false for an unscheduled proposal", async () => {
      expect(await multiSig.isProposalTimelockReached(proposalId)).to.be.false;
    });

    it("should return false for an unscheduled proposal even after sufficient delay has passed ", async () => {
      await timeTravel(delay);
      expect(await multiSig.isProposalTimelockReached(proposalId)).to.be.false;
    });

    it("should return false for a scheduled proposal whose time lock has not elapsed", async () => {
      await multiSig.connect(owner2).confirmProposal(proposalId);
      expect(await multiSig.isProposalTimelockReached(proposalId)).to.be.false;
    });
  });
});
