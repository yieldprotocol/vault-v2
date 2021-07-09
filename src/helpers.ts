import { Cauldron } from '../typechain/Cauldron'

export async function getLastVaultId(cauldron: Cauldron): Promise<string> {
  const logs = await cauldron.queryFilter(cauldron.filters.VaultBuilt(null, null, null, null))
  const event = logs[logs.length - 1]
  return event.args.vaultId
}