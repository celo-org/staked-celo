/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable no-unused-vars */
import {
  BaseContract,
  BigNumber as EthersBigNumber,
  CallOverrides,
  ContractTransaction,
  Overrides,
} from "ethers";

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

export interface DefaultGroupContract extends BaseContract {
  getActiveGroupsNumber(overrides?: CallOverrides): Promise<EthersBigNumber>;
  getActiveGroupsHead(
    overrides?: CallOverrides
  ): Promise<[string, string] & { head: string; previousAddress: string }>;
  getActiveGroupPreviousAndNext(
    key: string,
    overrides?: CallOverrides
  ): Promise<[string, string] & { previousAddress: string; nextAddress: string }>;
  activateGroup(
    group: string,
    lesser: string,
    greater: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<ContractTransaction>;
}

export interface OrderedGroup {
  group: string;
  stCelo: string;
  realCelo: string;
}
