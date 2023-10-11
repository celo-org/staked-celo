import { DeployFunction } from "@celo/staked-celo-hardhat-deploy/types";
import { parseUnits } from "ethers/lib/utils";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DAY, getImpersonatedSigner, setBalance } from "../../test-ts/utils";
import { BigNumber } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deploy } = hre.deployments;

  const { deployer, multisigOwner0, multisigOwner1 } = await hre.getNamedAccounts();
  const owners = [multisigOwner0, multisigOwner1];

  await deploy("MultiSig", {
    from: deployer,
    log: true,
    args: [3 * DAY],
    proxy: {
      proxyArgs: ["{implementation}", "{data}"],
      upgradeIndex: 0,
      proxyContract: "ERC1967Proxy",
      execute: {
        methodName: "initialize",
        args: [owners, 2, 7 * DAY],
      },
    },
  });

  // Setting the pauser via address impersonation. In a production envrionment,
  // this needs to be done via a MultiSig proposal.
  const pauser = await hre.deployments.get("Pauser");
  const multiSig = await hre.ethers.getContract("MultiSig");
  const multiSigSigner = await getImpersonatedSigner(multiSig.address, parseUnits("100"));
  await multiSig.connect(multiSigSigner).setPauser(pauser.address);
  // `getImpersonatedSigner above sets the balance of the MultiSig contract
  // address. Need to reset it back to 0 so tests can expect a clean slate.
  await setBalance(multiSig.address, BigNumber.from("0"));
};

func.id = "deploy_test_multisig";
func.tags = ["TestMultiSig"];
func.dependencies = ["TestPauser"];
export default func;
