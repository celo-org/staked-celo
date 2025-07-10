/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable no-unused-vars */
import { BaseContract, BigNumber as EthersBigNumber, ContractTransaction, Overrides } from "ethers";
import BigNumber from "bignumber.js";

export interface ValidatorGroupVote {
  address: string;
  votes: BigNumber;
}

export interface RebalanceContract extends BaseContract {
  rebalance(
    fromGroup: string,
    toGroup: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;
}

export interface ExpectVsReal {
  group: string;
  expected: EthersBigNumber;
  real: EthersBigNumber;
  diff: EthersBigNumber;
}

export interface OrderedGroup {
  group: string;
  stCelo: string;
  realCelo: string;
}
