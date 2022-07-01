export const executeAndWait = async (operation: any) => {
  const tx = await operation;
  await tx.wait();
};
