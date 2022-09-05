import { task, types } from "hardhat/config";
import { UPGRADE_PROPOSAL } from "./tasksNames";
const privateKey = process.env.DEPLOYER_PRIVATE_KEY;

// Defaults
const DEPLOYER = process.env.DEPLOYER;

task(UPGRADE_PROPOSAL, "Proposes upgrade of implementation of contract.")
  .addParam("multisig", "Multisig address.")
  .addParam("newImplementation", "New implementation address", undefined, types.string)
  .addParam(
    "destination",
    "Destination address = proxy address that will have implementation upgraded"
  )
  .addParam("from", "The address of the account used to deploy the contracts.")
  .addFlag(
    "usePrivateKey",
    "Determines if private key in environment is used or not. Private key will be used automatically if network url is a remote host."
  )
  .setAction(
    async (
      args: {
        from: string;
        multisig: string;
        newImplementation: string;
        usePrivateKey: boolean;
        destination: string;
      },
      hre
    ) => {
      try {
        console.log(`Starting ${UPGRADE_PROPOSAL} task...`);
        const networks = hre.config.networks;
        const targetNetwork = hre.network.name;

        if (targetNetwork !== "hardhat") {
          const deployer = { [targetNetwork]: DEPLOYER };
          hre.config.namedAccounts = {
            //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
            ...hre.config.namedAccounts,
            //@ts-ignore Computed Property [targetNetwork]
            deployer: { ...hre.config.namedAccounts.deployer, ...deployer },
          };
          hre.config.networks[targetNetwork].from = DEPLOYER;
        }

        if (args.from !== undefined) {
          networks[targetNetwork].from = args.from;
          hre.config.namedAccounts = {
            //@ts-ignore Property 'deployer' does not exist on type 'NetworkConfig'
            ...hre.config.namedAccounts,
            //@ts-ignore Computed Property [targetNetwork]
            deployer: { ...hre.config.namedAccounts.deployer, [targetNetwork]: args["from"] },
          };
        }

        hre.config.networks = networks;

        // User can optionally specify using a private key irrespective of deploying to remote network or not.
        if (args["usePrivateKey"]) {
          networks[targetNetwork].accounts = [`0x${privateKey}`];
        }
        const multisig = await hre.ethers.getContract("MultiSig");

        const upgradeEncoded = multisig.interface.encodeFunctionData("upgradeTo", [
          args.newImplementation,
        ]);
        const tx = await multisig
          .attach(args.multisig)
          .submitProposal([args.destination], [0], [upgradeEncoded]);
        await tx.wait();
      } catch (error) {
        console.log(error);
      }
    }
  );
