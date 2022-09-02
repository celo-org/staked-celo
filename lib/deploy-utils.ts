export const executeAndWait = async (operation: any) => {
  const tx = await operation;
  await tx.wait();
};

export function getNoProxy() {
  return Boolean(
    process.env.NO_PROXY?.toLocaleLowerCase() === "true" || process.env.NO_PROXY === "1"
  );
}

export function getNoDependencies() {
  return Boolean(
    process.env.NO_DEPENDENCIES?.toLocaleLowerCase() === "true" ||
      process.env.NO_DEPENDENCIES === "1"
  );
}
