import { mineBlocks } from "../test-ts/utils";

async function mineNBlocks(n: number) {
  mineBlocks(n, true);
}

mineNBlocks(35);
