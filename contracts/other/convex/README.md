# Convex as collateral

### Solving the parallel balances issue
The Yield Protocol keeps its own accounting in parallel to each ERC20 and ERC1155 that in interacts with. `Cauldron.balances` is a parallel of each token `ERC20.balanceOf`, `cauldron.give` and `cauldron.stir` are parallels of `ERC20.transfer`.

This causes issues because we need to checkpoint each Convex transfer. We can do that within the ERC20 accounting, but doing the same on the already deployed Yield Protocol accounting is harder. The best solution I could come up with (so far) is:

1. Remove `stir` and `give` access from Ladle.
2. Reinstate the ConvexModule for `addVault` and `removeVault`.
3. If `stir` or `give` are needed in the future at the Ladle level, they can be added through an integration. This would be a standalone contract that has `stir` and `give` permissions on the Cauldron, but that can be only called by the Ladle (using `ladle.route()`. This contract would keep list of allowed or forbidden parameters for the vaults being operated upon.