// XXX: this is a bit of a hack to make chai expectations
// work when matching bignumber.js type BigNumbers, which
// are used by ContractKit, and ethers.BigNumber, which
// have a slightly different setup.
//
// Essentially we have this happening:
// ethers.BigNumber.from(val)
// where val is a BigNumber.js instance from ContractKit
//
// This happens here: https://github.com/TrueFiEng/Waffle/blob/master/waffle-chai/src/matchers/bigNumber.ts#L54-L61
// And the best way of getting this to work was relying on this
// part of the ethers.BigNumber.from logic:
// https://github.com/ethers-io/ethers.js/blob/master/packages/bignumber/src.ts/bignumber.ts#L268-L273
// By providing a `toHexString` function on the BigNumber.js class,
// we implement the API required by ethers.BigNumber to be able to
// convert between instances.
//
// What follows is a fun typescript-y way of monkey-patching a 3rd party class.
// It's easy to forget that javascript fakes classes, prototype FTW.

import { BigNumber } from "bignumber.js";

class BigNumberExtended extends BigNumber {
  public toHexString(): string {
    return `0x${this.toString(16)}`;
  }
}

BigNumber.prototype = Object.create(BigNumberExtended.prototype);
BigNumber.prototype.constructor = BigNumber;
